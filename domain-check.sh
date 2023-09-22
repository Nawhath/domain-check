#!/usr/bin/env bash

#  will expire in 60-days or less:
#
#  $ domain-check -a -f domains -q -x 60 -e admin@qsncc.com
#

PATH=/bin:/usr/bin:/usr/local/bin:/usr/local/ssl/bin:/usr/sfw/bin
export PATH

# Who to page when an expired domain is detected (cmdline: -e)
ADMIN="nawhath.aek@qsncc.com"

# Number of days in the warning threshhold  (cmdline: -x)
WARNDAYS=90

# If QUIET is set to TRUE, don't print anything on the console (cmdline: -q)
QUIET="FALSE"

# Don't send emails by default (cmdline: -a)
ALARM="TRUE"

# Whois server to use (cmdline: -s)
#WHOIS_SERVER="whois.internic.org"
WHOIS_SERVER="th.whois-servers.net"

# Location of system binaries
AWK=`which awk`
WHOIS=`which whois`
DATE=`which date`
CUT=`which cut`
GREP=`which grep`
TR=`which tr`
MAIL=`which mail`

# Place to stash temporary files
WHOIS_TMP="/var/tmp/whois.$$"

#############################################################################
# Purpose: Convert a date from MONTH-DAY-YEAR to Julian format
# Acknowledgements: Code was adapted from examples in the book
#                   "Shell Scripting Recipes: A Problem-Solution Approach"
#                   ( ISBN 1590594711 )
# Arguments:
#   $1 -> Month (e.g., 06)
#   $2 -> Day   (e.g., 08)
#   $3 -> Year  (e.g., 2006)
#############################################################################
date2julian()
{
    if [ "${1} != "" ] && [ "${2} != ""  ] && [ "${3}" != "" ]
    then
         ## Since leap years add aday at the end of February,
         ## calculations are done from 1 March 0000 (a fictional year)
         d2j_tmpmonth=$((12 * ${3} + ${1} - 3))

         ## If it is not yet March, the year is changed to the previous year
         d2j_tmpyear=$(( ${d2j_tmpmonth} / 12))

         ## The number of days from 1 March 0000 is calculated
         ## and the number of days from 1 Jan. 4713BC is added
         echo $(( (734 * ${d2j_tmpmonth} + 15) / 24 -  2 * ${d2j_tmpyear} + ${d2j_tmpyear}/4
                       - ${d2j_tmpyear}/100 + ${d2j_tmpyear}/400 + $2 + 1721119 ))
    else
         echo 0
    fi
}

#############################################################################
# Purpose: Convert a string month into an integer representation
# Arguments:
#   $1 -> Month name (e.g., Sep)
#############################################################################
getmonth()
{
       LOWER=`tolower $1`

       case ${LOWER} in
             jan) echo 1 ;;
             feb) echo 2 ;;
             mar) echo 3 ;;
             apr) echo 4 ;;
             may) echo 5 ;;
             jun) echo 6 ;;
             jul) echo 7 ;;
             aug) echo 8 ;;
             sep) echo 9 ;;
             oct) echo 10 ;;
             nov) echo 11 ;;
             dec) echo 12 ;;
               *) echo  0 ;;
       esac
}

#############################################################################
# Purpose: Calculate the number of seconds between two dates
# Arguments:
#   $1 -> Date #1
#   $2 -> Date #2
#############################################################################
date_diff()
{
        if [ "${1}" != "" ] &&  [ "${2}" != "" ]
        then
                echo $(expr ${2} - ${1})
        else
                echo 0
        fi
}

##################################################################
# Purpose: Converts a string to lower case
# Arguments:
#   $1 -> String to convert to lower case
##################################################################
tolower()
{
     LOWER=`echo ${1} | ${TR} [A-Z] [a-z]`
     echo $LOWER
}

##################################################################
# Purpose: Access whois data to grab the registrar and expiration date
# Arguments:
#   $1 -> Domain to check
##################################################################
check_domain_status()
{
    local REGISTRAR=""
    # Avoid WHOIS LIMIT EXCEEDED - slowdown our whois client by adding 3 sec
    sleep 1
    # Save the domain since set will trip up the ordering
    DOMAIN=${1}
    TLDTYPE="`echo ${DOMAIN} | ${CUT} -d '.' -f3 | tr '[A-Z]' '[a-z]'`"
    if [ "${TLDTYPE}"  == "" ];
    then
            TLDTYPE="`echo ${DOMAIN} | ${CUT} -d '.' -f2 | tr '[A-Z]' '[a-z]'`"
    fi

    # Invoke whois to find the domain registrar and expiration date
    #${WHOIS} -h ${WHOIS_SERVER} "=${1}" > ${WHOIS_TMP}
    # Let whois select server

    WHS="$(${WHOIS} -h "whois.iana.org" "${TLDTYPE}" | ${GREP} 'whois:' | ${AWK} '{print $2}')"

    if [ "${TLDTYPE}" == "jp" ];
    then
        ${WHOIS} -h ${WHS} "${1}" > ${WHOIS_TMP}
    else
        ${WHOIS} -h ${WHS} "${1}" > ${WHOIS_TMP}
    fi

    if [ "${TLDTYPE}" == "aero" ];
    then
            ${WHOIS} -h whois.aero "${1}" > ${WHOIS_TMP}
    fi
    # Parse out the expiration date and registrar -- uses the last registrar it finds
    REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $2 != ""  { REGISTRAR=substr($2,2,17) } END { print REGISTRAR }'`

    if [ "${TLDTYPE}" == "uk" ]; # for .uk domain
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $0 != ""  { getline; REGISTRAR=substr($0,9,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "me" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $2 != ""  { REGISTRAR=substr($2,2,23) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "jp" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} '/Registrant/ && $2 != ""  { REGISTRAR=substr($2,1,17) } END { print REGISTRAR }'`
    # no longer shows Registrar name, so will use Status #
    elif [ "${TLDTYPE}" == "md" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Status:/ && $2 != ""  { REGISTRAR=substr($2,2,27) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "info" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $2 != ""  { REGISTRAR=substr($2,2,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "ca" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $0 != ""  { getline; REGISTRAR=substr($0,24,17) } END { print REGISTRAR }'`
        if [ "${REGISTRAR}" = "" ]
        then
                REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Sponsoring Registrar:/ && $2 != "" { REGISTRAR=substr($2,1,17) } END { print REGISTRAR }'`
        fi
    elif [ "${TLDTYPE}" == "edu" ]; # added by nixCraft 26-aug-2017
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrant:/ && $0 != ""  { getline;REGISTRAR=substr($0,1,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "cafe" ]; # added by @kode29 26-aug-2017
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $0 != "" { REGISTRAR=substr($0,12,17) } END { print REGISTRAR }'`

    elif [ "${TLDTYPE}" == "link" ]; # added by @kode29 26-aug-2017
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $0 != "" {  REGISTRAR=substr($0,12,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "blog" ]; # added by @kode29 26-aug-2017
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/Registrar:/ && $0 != "" {  REGISTRAR=substr($0,12,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "ru" -o "${TLDTYPE}" == "su" ]; # added 20141113
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/registrar:/ && $2 != "" { REGISTRAR=substr($2,6,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "cz" ]; # added by Minitram 20170830
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/registrar:/ && $2 != "" { REGISTRAR=substr($2,5,17) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "pl" ];
    then
        REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/REGISTRAR:/ && $0 != "" { getline; REGISTRAR=substr($0,0,35) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "xyz" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${GREP} Registrar: | ${AWK} -F: '/Registrar:/ && $0 != "" { getline; REGISTRAR=substr($0,12,35) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "se" -o "${TLDTYPE}" == "nu" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F: '/registrar:/ && $2 != "" { getline; REGISTRAR=substr($2,9,20) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "fi" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${GREP} 'registrar' | ${AWK} -F: '/registrar/ && $2 != "" { getline; REGISTRAR=substr($2,2,20) } END { print  REGISTRAR }'`
    elif [ "${TLDTYPE}" == "fr" -o "${TLDTYPE}" == "re" -o "${TLDTYPE}" == "tf" -o "${TLDTYPE}" == "yt" -o "${TLDTYPE}" == "pm" -o "${TLDTYPE}" == "wf" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${GREP} "registrar:" | ${AWK} -F: '/registrar:/ && $2 != "" { getline; REGISTRAR=substr($2,4,20) } END { print REGISTRAR }'`
    elif [ "${TLDTYPE}" == "dk" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${GREP} Copyright | ${AWK}  '{print $8, $9, $10}'`
    elif [ "${TLDTYPE}" == "tr" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${GREP} "Organization Name" -m 1 | ${AWK} -F: '{print $2}'`
    elif [ "${TLDTYPE}" == "it" ];
    then
       REGISTRAR=`cat ${WHOIS_TMP} | ${AWK} -F':' '/Registrar/ && $0 != ""  { getline;REGISTRAR=substr($0,16,32) } END { print REGISTRAR }'`
    fi

    # If the Registrar is NULL, then we didn't get any data
    if [ "${REGISTRAR}" = "" ]
    then
        prints "$DOMAIN" "Unknown" "Unknown" "Unknown" "Unknown"
        return
    fi

    # The whois Expiration data should resemble the following: "Expiration Date: 09-may-2008"

    if [ "${TLDTYPE}" == "info" -o "${TLDTYPE}" == "org" ];
    then
            tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expiry Date:/ { print $4 }'`
            tyear=`echo ${tdomdate} | ${CUT} -d'-' -f1`
            tmon=`echo ${tdomdate} | ${CUT} -d'-' -f2`
               case ${tmon} in
             1|01) tmonth=jan ;;
             2|02) tmonth=feb ;;
             3|03) tmonth=mar ;;
             4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
            tday=`echo ${tdomdate} | ${CUT} -d'-' -f3 | ${CUT} -d'T' -f1`
            DOMAINDATE=`echo $tday-$tmonth-$tyear`
    elif [ "${TLDTYPE}" == "md" ]; # for .md domain
    then
            tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expiration date:/ { print $3 }'`
            tyear=`echo ${tdomdate} | ${CUT} -d'-' -f1`
            tmon=`echo ${tdomdate} | ${CUT} -d'-' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                      *) tmonth=0 ;;
                esac
            tday=`echo ${tdomdate} | ${CUT} -d'-' -f3`
            DOMAINDATE=`echo $tday-$tmonth-$tyear`
    elif [ "${TLDTYPE}" == "uk" ]; # for .uk domain
    then
            DOMAINDATE=`cat ${WHOIS_TMP} | ${AWK} '/Renewal date:/ || /Expiry date:/ { print $3 }'`
    elif [ "${TLDTYPE}" == "jp" ]; # for .jp 2010/04/30
    then
            tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expires on/ { print $3 }'`
            tyear=`echo ${tdomdate} | ${CUT} -d'/' -f1`
            tmon=`echo ${tdomdate} | ${CUT} -d'/' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                      *) tmonth=0 ;;
                esac
            tday=`echo ${tdomdate} | ${CUT} -d'/' -f3`
            DOMAINDATE=`echo $tday-$tmonth-$tyear`
    elif [ "${TLDTYPE}" == "ca" ]; # for .ca 2010/04/30
    then
            tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expiry date/ { print $3 }'`
            tyear=`echo ${tdomdate} | ${CUT} -d'/' -f1`
            tmon=`echo ${tdomdate} | ${CUT} -d'/' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                      *) tmonth=0 ;;
                esac
            tday=`echo ${tdomdate} | ${CUT} -d'/' -f3`
            DOMAINDATE=`echo $tday-$tmonth-$tyear`
    elif [ "${TLDTYPE}" == "me" ]; # for .me domain
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Registry Expiry Date:/ { print $4 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`
    elif [ "${TLDTYPE}" == "ru" -o "${TLDTYPE}" == "su" ]; # for .ru and .su 2014/11/13
    then
           tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/paid-till:/ { print $2 }'`
           tyear=`echo ${tdomdate} | ${CUT} -d'-' -f1`
           tmon=`echo ${tdomdate} |${CUT} -d'-' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
           tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
           DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`
    elif [ "${TLDTYPE}" == "com" -o "${TLDTYPE}" == "net" -o "${TLDTYPE}" == "org"  -o "${TLDTYPE}" == "link" -o "${TLDTYPE}" == "blog" -o "${TLDTYPE}" == "cafe" -o "${TLDTYPE}" == "biz" -o "${TLDTYPE}" == "us" -o "${TLDTYPE}" == "mobi" -o "${TLDTYPE}" == "tv" -o "${TLDTYPE}" == "co" -o "${TLDTYPE}" == "pro" -o "${TLDTYPE}" == "cafe" -o "${TLDTYPE}" == "in" -o "${TLDTYPE}" == "cat" -o "${TLDTYPE}" == "asia" -o "${TLDTYPE}" == "cc" -o "${TLDTYPE}" == "college" -o "${TLDTYPE}" == "aero"  ]; # added on 26-aug-2017 by nixCraft
    then
           tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Registry Expiry Date:/ { print $NF }'`
           tyear=`echo ${tdomdate} | ${CUT} -d'-' -f1`
           tmon=`echo ${tdomdate} |${CUT} -d'-' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
           tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
           DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`
    elif [ "${TLDTYPE}" == "edu" ] # added on 26-aug-2017 by nixCraft
    then
           tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Domain expires:/ { print $NF }'`
           echo $tomdate
           tyear=`echo ${tdomdate} | ${CUT} -d'-' -f3`
           tmon=`echo ${tdomdate} |${CUT} -d'-' -f2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
           tday=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
           DOMAINDATE=`echo "${tday}-${tmon}-${tyear}"`

     elif [ "${TLDTYPE}" == "cz" ] # added on 20170830 by Minitram
     then
           tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/expire:/ { print $NF }'`
           echo $tomdate
           tyear=`echo ${tdomdate} | ${CUT} -d'.' -f3`
           tmon=`echo ${tdomdate} |${CUT} -d'.' -f2`
           case ${tmon} in
                 1|01) tmonth=jan ;;
                 2|02) tmonth=feb ;;
                 3|03) tmonth=mar ;;
                 4|04) tmonth=apr ;;
                 5|05) tmonth=may ;;
                 6|06) tmonth=jun ;;
                 7|07) tmonth=jul ;;
                 8|08) tmonth=aug ;;
                 9|09) tmonth=sep ;;
                 10) tmonth=oct ;;
                 11) tmonth=nov ;;
                 12) tmonth=dec ;;
                 *) tmonth=0 ;;
           esac
           tday=`echo ${tdomdate} | ${CUT} -d "." -f 1`
           DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "pl" ] # NASK
    then
          tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/renewal date:/ { print $3 }'`
          tyear=`echo ${tdomdate} | ${CUT} -d'.' -f1`
          tmon=`echo ${tdomdate} | ${CUT} -d'.' -f2`
          case ${tmon} in
             1|01) tmonth=jan ;;
             2|02) tmonth=feb ;;
             3|03) tmonth=mar ;;
             4|04) tmonth=apr ;;
             5|05) tmonth=may ;;
             6|06) tmonth=jun ;;
             7|07) tmonth=jul ;;
             8|08) tmonth=aug ;;
             9|09) tmonth=sep ;;
             10) tmonth=oct ;;
             11) tmonth=nov ;;
             12) tmonth=dec ;;
             *) tmonth=0 ;;
          esac
          tday=`echo ${tdomdate} | ${CUT} -d'.' -f3`
          DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "xyz" ];
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Registry Expiry Date:/ { print $4 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "se" -o "${TLDTYPE}" == "nu" ];
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/expires:/ { print $2 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "dk" ];
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expires:/ { print $2 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "fi" ];
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/expires/ { print $2 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "." -f 3`
        tmon=`echo ${tdomdate} | ${CUT} -d "." -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "." -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "fr" -o "${TLDTYPE}" == "re" -o "${TLDTYPE}" == "tf" -o "${TLDTYPE}" == "yt" -o "${TLDTYPE}" == "pm" -o "${TLDTYPE}" == "wf" ];
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expiry Date:/ { print $3 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3 | ${CUT} -d "T" -f 1`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "mx" ];      # added by nixCraft 07/jan/2019
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expiration Date:/ { print $3 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "it" ];      # added by nixCraft 07/jan/2019 based upon https://github.com/pelligrag
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expire Date:/ { print $3 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "ro" ];      # added by nixCraft 07/jan/2019
    then
        tdomdate=`cat ${WHOIS_TMP} | ${AWK} -F':' '/Expires On:/ { print $2 }'`
        tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
        tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
               case ${tmon} in
                     1|01) tmonth=jan ;;
                     2|02) tmonth=feb ;;
                     3|03) tmonth=mar ;;
                     4|04) tmonth=apr ;;
                     5|05) tmonth=may ;;
                     6|06) tmonth=jun ;;
                     7|07) tmonth=jul ;;
                     8|08) tmonth=aug ;;
                     9|09) tmonth=sep ;;
                     10) tmonth=oct ;;
                     11) tmonth=nov ;;
                     12) tmonth=dec ;;
                     *) tmonth=0 ;;
               esac
        tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3`
        DOMAINDATE=`echo "${tday}-${tmonth}-${tyear}"`

    elif [ "${TLDTYPE}" == "tr" ];
        then
                tdomdate=`cat ${WHOIS_TMP} | ${AWK} '/Expires/ { print substr($3, 1, length($3)-1) }'`
                tyear=`echo ${tdomdate} | ${CUT} -d "-" -f 1`
                tmon=`echo ${tdomdate} | ${CUT} -d "-" -f 2`
                tday=`echo ${tdomdate} | ${CUT} -d "-" -f 3`
                DOMAINDATE=`echo "${tday}-${tmon}-${tyear}"`

    # may work with others       ??? ;)
    else
    DOMAINDATE=`cat ${WHOIS_TMP} | ${AWK} '/Expiration/ { print $NF }'`
    fi

    #echo $DOMAINDATE # debug
    # Whois data should be in the following format: "13-feb-2006"
    IFS="-"
    set -- ${DOMAINDATE}
    MONTH=$(getmonth ${2})
    IFS=""

    # Convert the date to seconds, and get the diff between NOW and the expiration date
    DOMAINJULIAN=$(date2julian ${MONTH} ${1#0} ${3})
    DOMAINDIFF=$(date_diff ${NOWJULIAN} ${DOMAINJULIAN})

    if [ ${DOMAINDIFF} -lt 0 ]
    then
          if [ "${ALARM}" == "TRUE" ]
          then
                echo "The domain ${DOMAIN} has expired!" \
                | ${MAIL} -s "Domain ${DOMAIN} has expired!" ${ADMIN}
           fi

           prints "${DOMAIN}" "Expired" "${DOMAINDATE}" "${DOMAINDIFF}" "${REGISTRAR}"

    elif [ ${DOMAINDIFF} -lt ${WARNDAYS} ]
    then
           if [ "${ALARM}" == "TRUE" ]
           then
                    echo "The domain ${DOMAIN} will expire on ${DOMAINDATE}" \
                    | ${MAIL} -s "Domain ${DOMAIN} will expire in ${WARNDAYS}-days or less" ${ADMIN}
            fi
            prints "${DOMAIN}" "Expiring" "${DOMAINDATE}" "${DOMAINDIFF}" "${REGISTRAR}"
     else
            prints "${DOMAIN}" "Valid" "${DOMAINDATE}"  "${DOMAINDIFF}" "${REGISTRAR}"
     fi
}

####################################################
# Purpose: Print a heading with the relevant columns
# Arguments:
#   None
####################################################
print_heading()
{
        if [ "${QUIET}" != "TRUE" ]
        then
                printf "\n%-35s %-46s %-8s %-11s %-5s\n" "Domain" "Registrar" "Status" "Expires" "Days Left"
                echo "----------------------------------- ---------------------------------------------- -------- ----------- ---------"
        fi
}

#####################################################################
# Purpose: Print a line with the expiraton interval
# Arguments:
#   $1 -> Domain
#   $2 -> Status of domain (e.g., expired or valid)
#   $3 -> Date when domain will expire
#   $4 -> Days left until the domain will expire
#   $5 -> Domain registrar
#####################################################################
prints()
{
    if [ "${QUIET}" != "TRUE" ]
    then
            MIN_DATE=$(echo $3 | ${AWK} '{ print $1, $2, $4 }')
            printf "%-35s %-46s %-8s %-11s %-5s\n" "$1" "$5" "$2" "$MIN_DATE" "$4"
    fi
}

##########################################
# Purpose: Describe how the script works
# Arguments:
#   None
##########################################
usage()
{
        echo "Usage: $0 [ -e email ] [ -x expir_days ] [ -q ] [ -a ] [ -h ]"
        echo "          {[ -d domain_namee ]} || { -f domainfile}"
        echo ""
        echo "  -a               : Send a warning message through email "
        echo "  -d domain        : Domain to analyze (interactive mode)"
        echo "  -e email address : Email address to send expiration notices"
        echo "  -f domain file   : File with a list of domains"
        echo "  -h               : Print this screen"
        echo "  -s whois server  : Whois sever to query for information"
        echo "  -q               : Don't print anything on the console"
        echo "  -x days          : Domain expiration interval (eg. if domain_date < days)"
        echo ""
}

### Evaluate the options passed on the command line
while getopts ae:f:hd:s:qx: option
do
        case "${option}"
        in
                a) ALARM="TRUE";;
                e) ADMIN=${OPTARG};;
                d) DOMAIN=${OPTARG};;
                f) SERVERFILE=$OPTARG;;
                s) WHOIS_SERVER=$OPTARG;;
                q) QUIET="TRUE";;
                x) WARNDAYS=$OPTARG;;
                \?) usage
                    exit 1;;
        esac
done

### Check to see if the whois binary exists
if [ ! -f ${WHOIS} ]
then
        echo "ERROR: The whois binary does not exist in ${WHOIS} ."
        echo "  FIX: Please modify the \$WHOIS variable in the program header."
        exit 1
fi

### Check to make sure a date utility is available
if [ ! -f ${DATE} ]
then
        echo "ERROR: The date binary does not exist in ${DATE} ."
        echo "  FIX: Please modify the \$DATE variable in the program header."
        exit 1
fi

### Baseline the dates so we have something to compare to
MONTH=$(${DATE} "+%m")
DAY=$(${DATE} "+%d")
YEAR=$(${DATE} "+%Y")
NOWJULIAN=$(date2julian ${MONTH#0} ${DAY#0} ${YEAR})

### Touch the files prior to using them
touch ${WHOIS_TMP}

### If a HOST and PORT were passed on the cmdline, use those values
if [ "${DOMAIN}" != "" ]
then
        print_heading
        check_domain_status "${DOMAIN}"
### If a file and a "-a" are passed on the command line, check all
### of the domains in the file to see if they are about to expire
elif [ -f "${SERVERFILE}" ]
then
        print_heading
        while read DOMAIN
        do
                check_domain_status "${DOMAIN}"

        done < ${SERVERFILE}

### There was an error, so print a detailed usage message and exit
else
        usage
        exit 1
fi

# Add an extra newline
echo

### Remove the temporary files
rm -f ${WHOIS_TMP}

### Exit with a success indicator
exit 0
