#!/usr/bin/env bash
set -euo pipefail
curl -s -X POST http://127.0.0.1:8000/subgraphs/name/lvr/local \
  -H 'content-type: application/json' \
  --data '{"query":"{ liquidityActions(first:10, orderBy:blockNumber, orderDirection:desc){ id baseDelta quoteDelta reason txHash blockNumber } }"}'
echo
