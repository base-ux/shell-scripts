#!/usr/bin/ksh
#
# Delete core files
#

# Source common library file
BASE_DIR=/usr/scripts
SYS_LIB=${BASE_DIR}/lib/_sys.lib
if [[ ! -f ${SYS_LIB} ]]; then
    # If we can't source _sys.lib we can't do anything
    echo "$0: ${SYS_LIB} not found" >&2 && exit 1
fi
. ${SYS_LIB}

# Source reqired library files
eval $(sys_source_lib fs)

################
# Functions
################

# Show usage help
function prog_usage
{
    echo "Usage: ${PROG_NAME} [-c conffile] [-d \"dir ...\"]"
    exit 1
}

# Get command line arguments
function prog_getopts
{
    typeset _opt
    typeset _dir

    while getopts :c:d: _opt
    do
	case ${_opt} in
	    c)
		CONF_FILE="${OPTARG}"
		fs_is_abspath ${CONF_FILE} || CONF_FILE=${SYS_PWD}/${CONF_FILE}
		;;
	    d)
		# Collect values if the same option is used multiple times
		[[ -z "${_dir}" ]] && _dir="${OPTARG}" || _dir="${_dir} ${OPTARG}"
		;;
	    :)
		sys_err_msg "argument missing for option '${OPTARG}'"
		prog_usage
		;;
	    ?)
		sys_err_msg "wrong option '${OPTARG}'"
		prog_usage
		;;
	esac
    done
    shift $((${OPTIND} - 1))
    if [[ $# -ne 0 ]]; then
	sys_err_msg "wrong options '$@'"
	prog_usage
    fi
    # Set collected option values
    [[ -n "${_dir}" ]] && sys_setoptvar DELCORE_DIRS="${_dir}"
}

################
# Main
################

# Uncomment the next line for functions debug
#for i in $(typeset +f); do typeset -ft $i; done

# Default configuration file in ${CONF_DIR} directory
CONF_FILE=${CONF_DIR}/delcore.conf

# Default values for configuration variables
sys_setdefvar DELCORE_DIRS=""

# Get command line arguments
prog_getopts "$@"

# Read configuration file
sys_read_conf ${CONF_FILE}

# Set variables (from default, config, environment and options)
sys_setvars

#
# Well, we've got all to do the work. :)
#

# If directories list is not empty then find and delete
# all 'core' files in those directories
if [[ -n "${DELCORE_DIRS}" ]]; then
    for _dir in ${DELCORE_DIRS}
    do
	# Check if the entry is directory
	if [[ -d ${_dir} ]]; then
	    find -H ${_dir} -xdev -type f -name core -exec rm {} \; 2>/dev/null
	fi
    done
fi
