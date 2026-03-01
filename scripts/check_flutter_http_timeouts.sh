#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] missing required command: rg" >&2
  exit 1
fi

darts_raw="$(rg --files clients/shamell_flutter/lib -g '*.dart' || true)"
dart_files=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  dart_files+=("$line")
done <<< "$darts_raw"
if [[ "${#dart_files[@]}" -eq 0 ]]; then
  echo "[OK]   no Dart files found under clients/shamell_flutter/lib"
  exit 0
fi

errors=0
for file in "${dart_files[@]}"; do
  if ! perl - "$file" <<'PERL'
use strict;
use warnings;

my $file = shift @ARGV;
open my $fh, "<", $file or die "open $file: $!";
my @lines = <$fh>;
close $fh;

# Guard only files that import package:http.
my $uses_http_pkg = 0;
for my $ln (@lines) {
    if ($ln =~ /package:http\/http\.dart/) {
        $uses_http_pkg = 1;
        last;
    }
}
exit(0) if !$uses_http_pkg;

my $failed = 0;
for my $i (0 .. $#lines) {
    my $line = $lines[$i];
    next unless $line =~ /await\s+([A-Za-z_][A-Za-z0-9_\.]*)\s*\.\s*(get|post|put|delete|patch)\s*\(/;

    my $receiver = $1 // '';
    # Track obvious HTTP clients:
    # - http.get/post/... static calls
    # - _http.get/post/... instance client
    # - httpClient/client-like variables
    my $looks_http_client =
        ($receiver eq 'http') ||
        ($receiver =~ /(^|\.|_)http$/) ||
        ($receiver =~ /(^|\.|_)(httpclient|client)$/i) ||
        ($receiver =~ /Client$/);
    next unless $looks_http_client;

    my $has_timeout = ($line =~ /\.timeout\(/) ? 1 : 0;
    if (!$has_timeout) {
        my $upper = $i + 16;
        $upper = $#lines if $upper > $#lines;
        for my $j ($i + 1 .. $upper) {
            if ($lines[$j] =~ /\.timeout\(/) {
                $has_timeout = 1;
                last;
            }
            last if $lines[$j] =~ /;\s*$/;
        }
    }

    if (!$has_timeout) {
        print "$file:" . ($i + 1) . ":" . $line;
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
  echo "[FAIL] found await http.* calls without timeout guard" >&2
  echo "       Fix: add .timeout(const Duration(...)) to every awaited HTTP call." >&2
  exit 1
fi

echo "[OK]   all awaited Flutter http calls include timeout guards"
