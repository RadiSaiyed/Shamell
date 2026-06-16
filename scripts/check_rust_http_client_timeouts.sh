#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] missing required command: rg" >&2
  exit 1
fi

files_raw="$(rg --files services_rs crates_rs | rg 'src/.*\.rs$' || true)"
rs_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  rs_files+=("$line")
done <<< "$files_raw"

if [[ "${#rs_files[@]}" -eq 0 ]]; then
  echo "[OK]   no Rust source files found"
  exit 0
fi

errors=0
for file in "${rs_files[@]}"; do
  if ! perl - "$file" <<'PERL'
use strict;
use warnings;

sub brace_delta {
    my ($line) = @_;
    my $open = () = $line =~ /\{/g;
    my $close = () = $line =~ /\}/g;
    return $open - $close;
}

my $file = shift @ARGV;
open my $fh, "<", $file or die "open $file: $!";
my @lines = <$fh>;
close $fh;

# Ignore code inside #[cfg(test)] blocks, but continue scanning runtime code
# that may appear later in the file.
my @prod = ();
my $skip_depth = 0;
my $pending_cfg_test = 0;
for my $i (0 .. $#lines) {
    my $line = $lines[$i];

    if ($skip_depth > 0) {
        $skip_depth += brace_delta($line);
        $skip_depth = 0 if $skip_depth < 0;
        next;
    }

    if ($pending_cfg_test) {
        if ($line =~ /^\s*#\[/ || $line =~ /^\s*$/) {
            next;
        }
        my $delta = brace_delta($line);
        $skip_depth = $delta > 0 ? $delta : 0;
        $pending_cfg_test = 0;
        next;
    }

    if ($line =~ /^\s*#\s*\[cfg\(test\)\]\s*(.*)$/) {
        my $rest = $1 // '';
        if ($rest =~ /\S/) {
            # Handles single-line form like: #[cfg(test)] mod tests { ... }
            my $delta = brace_delta($rest);
            $skip_depth = $delta > 0 ? $delta : 0;
        } else {
            $pending_cfg_test = 1;
        }
        next;
    }

    push @prod, [($i + 1), $line];
}

my $failed = 0;

# Ban reqwest::Client::new() in runtime paths (requires explicit timeout config).
for my $i (0 .. $#prod) {
    my ($lineno, $line) = @{$prod[$i]};
    if ($line =~ /\breqwest::Client::new\(\)/) {
        print "$file:$lineno:$line";
        $failed = 1;
    }
}

# Ensure reqwest::Client::builder chains include both timeout and connect_timeout.
for (my $i = 0; $i <= $#prod; $i++) {
    my ($lineno, $line) = @{$prod[$i]};
    next unless $line =~ /\breqwest::Client::builder\s*\(/;

    my $has_timeout = 0;
    my $has_connect_timeout = 0;
    my $saw_build = 0;
    my $upper = $i + 30;
    $upper = $#prod if $upper > $#prod;
    for my $j ($i .. $upper) {
        my $scan = $prod[$j]->[1];
        $has_timeout = 1 if $scan =~ /\.timeout\s*\(/;
        $has_connect_timeout = 1 if $scan =~ /\.connect_timeout\s*\(/;
        if ($scan =~ /\.build\s*\(/) {
            $saw_build = 1;
            last;
        }
        last if $scan =~ /;\s*$/ && $j > $i;
    }

    if ($saw_build && (!$has_timeout || !$has_connect_timeout)) {
        print "$file:$lineno:$line";
        $failed = 1;
    }
}

exit($failed);
PERL
  then
    errors=1
  fi
done

if (( errors != 0 )); then
  echo "[FAIL] Rust reqwest clients in runtime paths must set timeout + connect_timeout" >&2
  echo "       Fix: configure both .timeout(...) and .connect_timeout(...) on each reqwest::Client::builder()." >&2
  exit 1
fi

echo "[OK]   Rust reqwest runtime clients configure timeout + connect_timeout"
