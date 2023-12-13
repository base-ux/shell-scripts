#!/usr/bin/ksh
#
# Backup configuration files and report differences
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
    echo "Usage: ${PROG_NAME} [-c conffile] [-d dir] [-M mode]"
    echo "          [-f \"file ...\"] [-l \"listfile ...\"]"
    echo "          [-m] [-t mailto]"
    exit 1
}

# Get command line arguments
function prog_getopts
{
    typeset _opt
    typeset _file _list

    while getopts :c:d:M:f:l:mt: _opt
    do
	case ${_opt} in
	    c)
		CONF_FILE="${OPTARG}"
		fs_is_abspath ${CONF_FILE} || CONF_FILE=${SYS_PWD}/${CONF_FILE}
		;;
	    d)
		sys_setoptvar CFBACKUP_DIR="${OPTARG}"
		;;
	    M)
		sys_setoptvar CFBACKUP_MODE="${OPTARG}"
		;;
	    f)
		# Collect values if the same option is used multiple times
		[[ -z "${_file}" ]] && _file="${OPTARG}" || _file="${_file} ${OPTARG}"
		;;
	    l)
		# Collect values if the same option is used multiple times
		[[ -z "${_list}" ]] && _list="${OPTARG}" || _list="${_list} ${OPTARG}"
		;;
	    m)
		sys_setoptvar CFBACKUP_MAIL="yes"
		;;
	    t)
		sys_setoptvar CFBACKUP_MAILTO="${OPTARG}"
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
    [[ -n "${_file}" ]] && sys_setoptvar CFBACKUP_FILE="${_file}"
    [[ -n "${_list}" ]] && sys_setoptvar CFBACKUP_LIST="${_list}"
}

# Check paths and process directories
function prog_check_paths
{
    typeset _p

    # Read paths from stdin
    while read _p
    do
	# Check absolute path for the path
	fs_is_abspath "${_p}" || {
	    sys_warn_msg "${_p} is not absolute path"
	    continue
	}
	# Check '/' in the end of path
	if [[ "${_p}" = */ ]]; then
	    _p=${_p%/}	# Chop '/' from end of path
	    # If the path is directory then find all files in it
	    [[ -d ${_p} ]] && find -L ${_p} -type f -print 2>/dev/null
	else
	    # Just print path
	    echo "${_p}"
	fi
    done
}

# Process specified file and do all the work
function prog_process_file
{
    typeset _f="$1"
    typeset _bf _obf
    typeset _rc

    # Check absolute path for the file
    fs_is_abspath "${_f}" || { sys_warn_msg "${_f} is not absolute path"; return; }

    # _bf is backup file path
    # _obf is backup file path with date extension ("old" backup file)
    _bf="${CFBACKUP_DIR}${_f}"
    _obf="${_bf}.${CUR_FDATE}"

    if [[ -f "${_f}" ]]; then
	if [[ -f "${_bf}" ]]; then
	    # If backup file exists then compare original file with backup,
	    # if there are any differences then
	    # move backup file to "old" backup
	    # and copy original to backup
	    diff -u "${_bf}" "${_f}" >>${TMP_FILEOUT} 2>/dev/null
	    _rc=$?
	    if [[ ${_rc} -eq 1 ]]; then
		# There are differences
		mv -f "${_bf}" "${_obf}" 2>/dev/null
		[[ $? -ne 0 ]] && { sys_warn_msg "can't move file ${_bf}"; return; }
		cp -p "${_f}" "${_bf}" 2>/dev/null
		[[ $? -ne 0 ]] && { sys_warn_msg "can't copy file ${_f}"; return; }
	    fi
	else
	    # If backup file does not exist then just copy original to it
	    # Create destination directories before copying
	    _bdir=$(dirname "${_bf}")
	    if [[ ! -d "${_bdir}" ]]; then
		mkdir -p -m ${CFBACKUP_MODE} "${_bdir}" 2>/dev/null
		[[ $? -ne 0 ]] && { sys_warn_msg "can't create directory ${_bdir}"; return; }
	    fi
	    cp -p "${_f}" "${_bf}" 2>/dev/null
	    [[ $? -ne 0 ]] && { sys_warn_msg "can't copy file ${_f}"; return; }
	fi
    fi
}

################
# Main
################

# Uncomment the next line for functions debug
#for i in $(typeset +f); do typeset -ft $i; done

# Default configuration file in ${CONF_DIR} directory
CONF_FILE=${CONF_DIR}/cfbackup.conf

# Default values for configuration variables
sys_setdefvar CFBACKUP_DIR="/var/cfbackup"
sys_setdefvar CFBACKUP_MODE="750"
sys_setdefvar CFBACKUP_MAIL="no"
sys_setdefvar CFBACKUP_MAILTO="root"
sys_setdefvar CFBACKUP_FILE=""
sys_setdefvar CFBACKUP_LIST=""

# Get command line arguments
prog_getopts "$@"

# Read configuration file
sys_read_conf ${CONF_FILE}

# Set variables (from default, config, environment and options)
sys_setvars

#
# Well, we've got all for the work. :)
#

# Current date:
# CUR_DATE is used in mail subject
# CUR_FDATE is used as backup files extension
CUR_DATE="$(date +%Y-%m-%d)"
CUR_FDATE="$(echo ${CUR_DATE} | sed 's/-//g')"

# Subject for mail message
MAIL_SUBJ="${SYS_HOST}: configuration differences on ${CUR_DATE}"

# Temporary files names
_TMP_FILE=${TMP_DIR}/${PROG_NAME}.$$.${RANDOM}
TMP_FILELST=${_TMP_FILE}.lst
TMP_FILEOUT=${_TMP_FILE}.out

# Check backup directory option
if [[ -z "${CFBACKUP_DIR}" ]]; then
    sys_err_exit "CFBACKUP_DIR must be set"
else
    fs_is_abspath ${CFBACKUP_DIR} || \
	sys_err_exit "CFBACKUP_DIR must be absolute path"
fi

# If CFBACKUP_FILE and CFBACKUP_LIST are empty
# then we should not do anything
if [[ -z "${CFBACKUP_FILE}" && -z "${CFBACKUP_LIST}" ]]; then
    sys_err_msg "neither <file> nor <listfile> is set"
    prog_usage
fi

# Empty temporary files, exit if the files can't be created
: >${TMP_FILELST}
[[ $? -ne 0 ]] && sys_err_exit "can't create file ${TMP_FILELST}"
: >${TMP_FILEOUT}
[[ $? -ne 0 ]] && sys_err_exit "can't create file ${TMP_FILEOUT}"

# Remove temporary files if the script is trapped
trap "rm -f ${TMP_FILELST} ${TMP_FILEOUT}" 1 2 15

# Form the list of files to process in the TMP_FILELST file:
# Process the list of files in CFBACKUP_FILE
if [[ -n "${CFBACKUP_FILE}" ]]; then
    for _f in ${CFBACKUP_FILE}
    do
	echo "${_f}"
    done | prog_check_paths >>${TMP_FILELST}
fi
# Process the lists of files in CFBACKUP_LIST
if [[ -n "${CFBACKUP_LIST}" ]]; then
    for _f in ${CFBACKUP_LIST}
    do
	# If the path is not absolute
	# first check path relative to current working directory
	# then presume it relative to CONF_DIR directory
	fs_is_abspath ${_f} || {
	    [[ -f ${SYS_PWD}/${_f} ]] && _f=${SYS_PWD}/${_f} || \
		_f=${CONF_DIR}/${_f}
	}
	# Read file and add its content to TMP_FILELST file
	fs_read_listfile "${_f}" | prog_check_paths >>${TMP_FILELST}
    done
fi

# If the resulting list is not empty then do the work
if [[ -s ${TMP_FILELST} ]]; then
    # Create backup directory if it's not exist
    if [[ ! -d ${CFBACKUP_DIR} ]]; then
	mkdir -p -m ${CFBACKUP_MODE} ${CFBACKUP_DIR} 2>/dev/null
	[[ $? -ne 0 ]] && \
	    sys_err_msg "can't create directory ${CFBACKUP_DIR}"
    fi
    # Check backup directory existance one more time
    if [[ -d ${CFBACKUP_DIR} ]]; then
	# Sort the resulting list and process it
	cat ${TMP_FILELST} | sort -u | while read _f
	do
	    prog_process_file ${_f}
	done
	# If there are differences
	if [[ -s ${TMP_FILEOUT} ]]; then
	    # Send differences to CFBACKUP_MAILTO recipients
	    # only if -m option is set
	    if [[ "${CFBACKUP_MAIL}" = "yes" && -n "${CFBACKUP_MAILTO}" ]]; then
		cat ${TMP_FILEOUT} | mail -s "${MAIL_SUBJ}" "${CFBACKUP_MAILTO}"
	    fi
	fi
    fi
fi

# Delete temporary file
rm -f ${TMP_FILELST} ${TMP_FILEOUT}
