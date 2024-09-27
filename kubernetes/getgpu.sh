#!/usr/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "${GREEN}GETTING GPU INFO${NC}"
echo ""
kubectl get nodes -o=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{' i915: '}{.status.allocatable.gpu\.intel\.com/i915}{'\n'}"
echo ""
