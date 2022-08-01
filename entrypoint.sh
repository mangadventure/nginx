#!/bin/sh

trap 'nginx -s quit' TERM

exec nginx "$@"
