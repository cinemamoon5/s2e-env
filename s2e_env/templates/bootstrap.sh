#!/bin/bash
#
# This file was automatically generated by s2e-env at {{ current_time | datetimefilter }}
#
# This bootstrap file is used to control the execution of the Linux target
# program in S2E.
#
# When you run launch-s2e.sh, the guest VM calls s2eget to fetch and execute this
# bootstrap script. This bootstrap script and the S2E config file determine how
# the target program is analyzed.
#

set -x

# To save you the hassle of rebuilding the image every time you want to update
# S2E's guest tools, the first thing that we do is get the latest versions of
# the guest tools.
function update_guest_tools {
    local COMMON_TOOLS
    local GUEST_TOOLS

    COMMON_TOOLS="s2ecmd s2eget s2eput"
    GUEST_TOOLS="$COMMON_TOOLS $(target_tools)"
    for TOOL in ${GUEST_TOOLS}; do
        ./s2eget guest-tools/${TOOL}
        chmod +x ${TOOL}
    done
}

function prepare_target {
    local TARGET
    TARGET=$1

    # Make sure that the target is executable
    chmod +x ${TARGET}
}

# This prepares the symbolic file inputs.
# This function takes as input an optional seed file name.
# If the seed file is present, the commands makes the seed symbolic.
# Otherwise, it creates an empty file.
#
# Symbolic files must be stored in a ram disk, as only memory (and cpu)
# is capable of holding symbolic data.
#
# This function prints the path to the symbolic file on stdout.
function prepare_inputs {
    local SEED_FILE
    local SYMB_FILE

    # This can be empty if there are no seed files
    SEED_FILE="$1"
    SYMB_FILE="/tmp/input"

    if [ "x$SEED_FILE" = "x" ]; then
        # Create a symbolic file of size 256 bytes.
        # Note: you can customize this commands according to your needs.
        # You could, e.g., use non-zero input, different sizs, etc.
        truncate -s 256 ${SYMB_FILE}

        if [ $? -ne 0 ]; then
            ./s2ecmd kill 1 "Failed to create symbolic file"
            exit 1
        fi
    else
        cp "$SEED_FILE" "$SYMB_FILE"
    fi

    # Make thie file symbolic
    ./s2ecmd symbfile ${SYMB_FILE}
    echo $SYMB_FILE
}

# This function executes the target program given in arguments.
#
# There are two versions of this function:
#    - without seed support
#    - with seed support (-s argument when creating projects with s2e_env)
function execute {
    local TARGET
    local SEED_FILE

    TARGET=$1

    prepare_target "$TARGET"

    {% if use_seeds %}
    # In seed mode, state 0 runs in an infinite loop trying to fetch and
    # schedule new seeds. It works in conjunction with the SeedSearcher plugin.
    # The plugin schedules state 0 only when seeds are available.

    # Enable seeds and wait until a seed file is available. If you are not
    # using seeds then this loop will not affect symbolic execution - it will
    # simply never be scheduled.
    ./s2ecmd seedsearcher_enable
    while true; do
        SEED_FILE=$(./s2ecmd get_seed_file)

        if [ $? -eq 255 ]; then
            # Avoid flooding the log with messages if we are the only runnable
            # state in the S2E instance
            sleep 1
            continue
        fi

        break
    done

    if [ -n "${SEED_FILE}" ]; then
        execute_target_with_seed "${TARGET}" "${SEED_FILE}"
    else
        # If there are no seeds available, execute the seedless instance.
        # The SeedSearcher only schedules the seedless instance once.
        execute_target "${TARGET}"
    fi

    {% else %}
    execute_target "${TARGET}"
    {% endif %}
}

###############################################################################
# This section contains target-specific code

{% include '%s' % target_bootstrap_template %}

###############################################################################


update_guest_tools

# Don't print crashes in the syslog. This prevents unnecessary forking in the
# kernel
sudo sysctl -w debug.exception-trace=0

# Prevent core dumps from being created. This prevents unnecessary forking in
# the kernel
ulimit -c 0

# Ensure that /tmp is mounted in memory (if you built the image using s2e-env
# then this should already be the case. But better to be safe than sorry!)
if ! mount | grep "/tmp type tmpfs"; then
    sudo mount -t tmpfs -osize=10m tmpfs /tmp
fi

target_init

# Download the target file to analyze
./s2eget "{{ target }}"

# Run the analysis
execute "./{{ target }}"

# Kill states before exiting
./s2ecmd kill 0 "'{{ target }}' state killed"
