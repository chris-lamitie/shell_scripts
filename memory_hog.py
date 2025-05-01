#!/usr/bin/env python3
#
# This script consumes 10MB of memory per iteration until the server runs out of memory.
# This is used for testing ulmits and cstate settings. feel free to change "10" to any
# other value, but remember to change all three 10's found below.
#
# Short ulmit tutorial:
# set ulmit in kb thusly: ulimit -v 256000 <-- is 250MB
#                         ulimit -v 1048576 <-- is 1 GiB
# Confirm your uslimit with: ulimit -H -v
#
# To reset ulimit, end your shell and start a new one.
#
# You can try a subshell: (ulimit -v 1048576; ./memory_hog.py)
#
import time

data = []
try:
    while True:
        # Allocate 10 MB at a time
        data.append(' ' * 10 * 1024 * 1024)
        print(f"Allocated {len(data)*10} MB")
        time.sleep(0.5)
except MemoryError:
    print("💥 MemoryError: limit exceeded!")
