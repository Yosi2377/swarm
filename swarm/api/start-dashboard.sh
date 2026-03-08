#!/bin/bash
cd "$(dirname "$0")" && node server.js &
echo "Dashboard running at http://95.111.247.22:9200"
