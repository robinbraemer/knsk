#!/bin/bash

# ----------------------------------------------------------------------------
#
# knsk.sh
#
# This script delete Kubernetes' namespaces that stuck in Terminanting status
#
#                                                          thyarles@gmail.com
#
# ----------------------------------------------------------------------------

# Variables
  set -u       # Ensure declaration of variables before use it
  K='kubectl'  # Short for kubectl
  DELBRK=0     # Don't delete broken API by default
  DELRES=0     # Don't delete inside resources by default
  FORCE=0      # Don't force deletion with kubeclt proxy by default
  CLEAN=0      # Start clean flag
  FOUND=0      # Start found flag
  KPORT=8765   # Default port to up kubectl proxy
  TIME=15      # Default timeout to wait for kubectl command responses
  WAIT=60      # Default time to wait Kubernetes do clean deletion
  C='\e[96m'   # Cyan
  M='\e[95m'   # Magenta
  B='\e[94m'   # Blue
  Y='\e[93m'   # Yellow
  G='\e[92m'   # Green
  R='\e[91m'   # Red
  S='\e[0m'    # Reset
  N='\n'       # New line

# Function to show help
  show_help () {
    echo -e "\n$(basename $0) [options]\n"
    echo -e "  --skip-tls\t\tSet --insecure-skip-tls-verify on kubectl call"
    echo -e "  --delete-api\t\tDelete broken API founded in your Kubernetes cluster"
    echo -e "  --delete-resource\tDelete resources founded in your stucked namespaces"
    echo -e "  --delete-all\t\tDelete resources of stucked namespaces and broken API"
    echo -e "  --force\t\tForce deletion of stucked namespaces even if a clen deletion fail"
    echo -e "  --port {number}\tUp kubectl prosy on this port, default is 8765"
    echo -e "  --timeout {number}\tMax time (in seconds) to wait for Kubectl commands"
    echo -e "  --no-color\t\tAll output without colors (useful for scripts)"
    echo -e "  -h --help\t\tShow this help\n"
    exit 0
  }

# Check for parameters
  while (( "$#" )); do
    case $1 in
      --skip-tls)	
        K=$K" --insecure-skip-tls-verify"
        shift
      ;;
      --delete-api)
        DELBRK=1
        shift
      ;;
      --delete-resource)
        DELRES=1
        shift
      ;;
      --delete-all)
        DELBRK=1
        DELRES=1
        shift
      ;;
      --force)
        FORCE=1
        shift
      ;;
      --port)
        shift
        # Check if the port is a number
        [ "$1" -eq "$1" ] 2>/dev/null || show_help
        KPORT=$1
        shift
      ;;
      --timeout)
        shift
        # Check if the time is a number
        [ "$1" -eq "$1" ] 2>/dev/null || show_help
        TIME=$1
        shift
      ;;
      --no-color)
        C=''; M=''; B=''; Y=''; G=''; R=''; S=''
        shift
      ;;
      *) show_help
    esac
  done

# Function to format and print messages
  pp () {
    # First argument is the type of message
    # Second argument is the message
    case $1 in
      t1    ) echo  -e "$N$G$2$S"                        ;;
      t2    ) echo  -e "$N$Y$2$S"                        ;;
      t3    ) echo  -e "$Y.: $2"                         ;;
      t4    ) echo  -e "$Y   > $2"                       ;;
      t2n   ) echo -ne "$N$Y$2...$S"                     ;;
      t3n   ) echo -ne "$Y.: $2...$S"                    ;;
      t4n   ) echo -ne "$Y   > $2...$S"                  ;;
      ok    ) echo  -e "$G ok$S"                         ;;
      found ) echo  -e "$C found$S"                      ;;
      nfound) echo  -e "$G not found$S"                  ;;
      del   ) echo  -e "$G deleted$S"                    ;;
      skip  ) echo  -e "$C deletion skipped$S"           ;;
      error ) echo  -e "$R error$S"                      ;;
      fail  ) echo  -e "$R fail$S"; echo -e "$N$R$2.$S$N";
              exit 1
    esac
  }

# Function to sleep for a while
  timer () {
    OLD_IFS="$IFS"; IFS=:; set -- $*; SECS=$1; MSG=$2
    while [ $SECS -gt 0 ]; do
      sleep 1 &
      printf "\r.: $Y$MSG$S... $G%02d:%02d$S" $(( (SECS/60)%60)) $((SECS%60))
      SECS=$(( $SECS - 1 ))
      wait
    done
    printf "\r.: $Y$MSG...$G ok      $S$N" 
    set -u; IFS="$OLD_IFS"; export CLEAN=0
  }  

# Check if kubectl is available
  pp t1 "Kubernetes NameSpace Killer"
  pp t2n "Checking if kubectl is configured"
  $K cluster-info >& /dev/null; E=$?
  [ $E -gt 0 ] && pp fail "Check if the kubeclt is installed and configured"
  pp ok

# Check for broken APIs
  pp t2n "Checking for unavailable apiservices"
  APIS=$($K get apiservice | grep False | cut -f1 -d ' ')
  # More info in https://github.com/kubernetes/kubernetes/issues/60807#issuecomment-524772920
  if [ "x$APIS" == "x" ]; then
    pp nfound  # Nothing found, go on
  else
    pp found   # Something found, let's deep in
    for API in $APIS; do
      pp t3n "Broken -> $R$API$S"
      if (( $DELBRK )); then
        CLEAN=1
        timeout $TIME $K delete apiservice $API >& /dev/null; E=$?
        if [ $E -gt 0 ]; then pp error; else pp del; fi
      else
        pp skip
      fi
    done
    [ $CLEAN -gt 0 ] && timer $WAIT "apiresources deleted, waiting to see if Kubernetes do a clean namespace deletion"
  fi

# Search for resources in stucked namespaces
  pp t2n "Checking for resources on stucked namespaces"
  NSS=$($K get ns 2>/dev/null | grep Terminating | cut -f1 -d ' ')
  if [ "x$NSS" == "x" ]; then
    pp nfound
  else
    pp found
    for NS in $NSS; do
      pp t3n "Checking resources in namespace $R$NS$S"
      RESS=$($K api-resources --verbs=list --namespaced -o name 2>/dev/null | \
           xargs -n 1 $K get -n $NS --no-headers=true --show-kind=true 2>/dev/null | \
           grep -v Cancelling | cut -f1 -d ' ')
      if [ "x$RESS" == "x" ]; then
        pp nfound
      else
        pp found
        for RES in $RESS; do
          pp t4n $RES 
          if (( $DELRES )); then
            CLEAN=1
            # Try to delete by delete command
            timeout $TIME $K -n $NS --grace-period=0 --force=true delete $RES > /dev/null 2>&1; E=$?
            if [ $E -gt 0 ]; then 
              # Try to delete by patching
              timeout $TIME $K -n $NS patch $RES -p '{"metadata":{"finalizers":null}}' > /dev/null 2>&1; E=$?
              if [ $E -gt 0 ]; then pp error; else pp del; fi
            else
              pp del
            fi
          else
            pp skip
          fi
        done        
      fi      
    done
    [ $CLEAN -gt 0 ] && timer $WAIT "resources deleted, waiting to see if Kubernetes do a clean namespace deletion"
  fi

# Search for resisted stucked namespaces and force deletion if --force is passed
  if (( $FORCE )); then

    pp t2 "Forcing deletion of stucked namespaces"

    # Check if --force is used without --delete-resouce
    pp t3n "Checking compliance of --force option"
    (( $DELRES )) || pp fail "The '--force' option must be used with '--delelete-all' or '--delete-resource options'"
    pp ok
    
    # Try to get the access token
    pp t3n "Getting the access token to force deletion"
    TOKEN=$($K -n default describe secret \
          $($K -n default get secrets | grep default | cut -f1 -d ' ') | \
          grep -E '^token' | cut -f2 -d':' | tr -d '\t' | tr -d ' '); E=$?
    [ $E -gt 0 ] && pp fail "Unable to gat the token to force a deletion"
    pp ok

    # Try to up the kubectl proxy
    pp t3n "Starting kubectl proxy"
    $K proxy --accept-hosts='^localhost$,^127\.0\.0\.1$,^\[::1\]$' -p $KPORT  >> /tmp/proxy.out 2>&1 &
    E=$?; KPID=$!
    [ $E -gt 0 ] && pp fail "Unable start a proxy, check if the port '$KPORT' is free. Change it by passing '--port number' flag"
    pp ok

    # Force namespace deletion
    pp t3n "Checking for resisted stucked namespaces to force deletion"
    NSS=$($K get ns 2>/dev/null | grep Terminating | cut -f1 -d ' ')
    if [ "x$NSS" == "x" ]; then
      pp nfound
    else
      pp found; FOUND=1
      for NS in $NSS; do
        pp t4n "Forcing deletion of $NS"
        TMP=/tmp/$NS.json
        $K get ns $NS -o json > $TMP 2>/dev/null
        if [[ "$OSTYPE" == "darwin"* ]]; then
          sed -i '' "s/\"kubernetes\"//g" $TMP
        else
          sed -i s/\"kubernetes\"//g $TMP
        fi
        curl -s -o $TMP.log -X PUT --data-binary @$TMP http://localhost:$KPORT/api/v1/namespaces/$NS/finalize \
             -H "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" --insecure
        sleep 5
        pp ok
      done
    fi

    # Close the proxy
    pp t3n "Stopping kubectl proxy"
    kill $KPID; E=$?
    wait $KPID 2>/dev/null
    if [ $E -gt 0 ]; then pp error; else pp ok; fi
  fi

# End of script
  (( $FOUND )) || (( $DELBRK )) || (( $DELRES )) || pp t2 ":: Download and run '$G./knsk.sh --help$Y' if you want to delete resources by this script."
  pp t2 ":: Done in $SECONDS seconds.$N"
  exit 0
