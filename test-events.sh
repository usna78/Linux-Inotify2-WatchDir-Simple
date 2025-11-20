#!/bin/bash
#
# ywatch Event Testing Script
# This script triggers all available inotify events to test ywatch monitoring
#
# Usage: ./test-events.sh
#

TEST_DIR="/home/openxfer/test/ywatch/event_test"
SLEEP_TIME=2

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  ywatch Event Testing Script"
echo "=========================================="
echo
echo "Test directory: $TEST_DIR"
echo "Sleep between tests: ${SLEEP_TIME}s"
echo

# Create test directory if it doesn't exist
mkdir -p "$TEST_DIR"

# Function to run test and wait
run_test() {
    local test_num=$1
    local test_name=$2
    local command=$3

    echo -e "${BLUE}Test $test_num: $test_name${NC}"
    echo "Command: $command"
    eval "$command"
    echo -e "${GREEN}✓ Triggered${NC}"
    echo
    sleep $SLEEP_TIME
}

# Test 1: CREATE event
run_test 1 "CREATE" \
    "touch '$TEST_DIR/create_test.txt'"

# Test 2: MODIFY event
run_test 2 "MODIFY" \
    "echo 'modified content' >> '$TEST_DIR/create_test.txt'"

# Test 3: CLOSE_WRITE event (write and close in one operation)
run_test 3 "CLOSE_WRITE" \
    "echo 'close write test' > '$TEST_DIR/close_test.txt'"

# Test 4: ATTRIB event (change permissions)
run_test 4 "ATTRIB" \
    "chmod 755 '$TEST_DIR/create_test.txt'"

# Test 5: ACCESS event (read file)
run_test 5 "ACCESS" \
    "cat '$TEST_DIR/create_test.txt' > /dev/null"

# Test 6: OPEN event
run_test 6 "OPEN" \
    "cat '$TEST_DIR/close_test.txt' > /dev/null"

# Test 7: CLOSE event (will trigger on the cat read)
echo -e "${BLUE}Test 7: CLOSE${NC}"
echo "Note: CLOSE event already triggered by ACCESS/OPEN tests above"
echo -e "${GREEN}✓ Already triggered${NC}"
echo
sleep $SLEEP_TIME

# Test 8: MOVE_TO event (move file into watched directory)
run_test 8 "MOVE_TO" \
    "touch /tmp/move_test.txt && mv /tmp/move_test.txt '$TEST_DIR/moved_in.txt'"

# Test 9: MOVE_FROM event (move file out of watched directory)
run_test 9 "MOVE_FROM" \
    "mv '$TEST_DIR/moved_in.txt' /tmp/moved_out.txt"

# Test 10: MOVE event (rename within watched directory)
run_test 10 "MOVE (rename)" \
    "touch '$TEST_DIR/rename_test.txt' && sleep 1 && mv '$TEST_DIR/rename_test.txt' '$TEST_DIR/renamed.txt'"

# Test 11: DELETE event
run_test 11 "DELETE" \
    "rm '$TEST_DIR/create_test.txt' '$TEST_DIR/close_test.txt' '$TEST_DIR/renamed.txt'"

# Cleanup temp file if it exists
rm -f /tmp/moved_out.txt

echo "=========================================="
echo "  Testing Complete!"
echo "=========================================="
echo
echo "Check the following for results:"
echo "  1. Console output (if ywatch running in foreground)"
echo "  2. Log file: /home/openxfer/test/ywatch/logs/event-test.log"
echo "  3. Email: russ@opentransfer.net"
echo
echo "Expected: 11 different event types triggered"
echo
