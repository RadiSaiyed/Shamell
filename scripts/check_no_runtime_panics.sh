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
        # Allow stacked attributes before the cfg(test) target item.
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
for my $entry (@prod) {
    my ($lineno, $line) = @$entry;
    next unless $line =~ /\.expect\(|\.unwrap\(|panic!\(|todo!\(|unimplemented!\(/;
    # Allow compile-time constant regex construction in static initializers.
    next if $line =~ /Regex::new\(/;
    print "$file:$lineno:$line";
    $failed = 1;
}

exit($failed);
PERL
  then
    errors=1
  fi
done

if (( errors != 0 )); then
  echo "[FAIL] runtime panic-prone calls found in Rust non-test paths" >&2
  echo "       Fix: replace with error propagation/map_err and fail-closed ApiError handling." >&2
  exit 1
fi

echo "[OK]   no runtime panic-prone calls in Rust non-test paths"
