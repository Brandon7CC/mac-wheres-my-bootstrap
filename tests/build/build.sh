#!/bin/sh

src="../src/xpc_connection_tester.c"
executable="../bin/xpcConnTest1"

gcc -g -Wall $src -o $executable
