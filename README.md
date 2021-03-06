# knsk - Kubernetes namespace killer

This tool is aimed to kill namespaces that stuck in Terminating mode after you try to delete it. Just calling this script without flags, it shows you the possible problemns that put your namespace in forever terminating mode.

It automates the tips by https://github.com/alvaroaleman in https://github.com/kubernetes/kubernetes/issues/60807#issuecomment-524772920

If it doesn't work for you, please, let me know. It is hard to force namespace in Terminating mode just to test it.

### Basic usage
     curl -s https://raw.githubusercontent.com/thyarles/knsk/master/knsk.sh | bash 
     wget -q https://raw.githubusercontent.com/thyarles/knsk/master/knsk.sh -O - | bash 
     
In this mode, this script only shows the possible causes that put your namespaces in **Terminating** mode. If you want this script to try to fix the mess, clone this repository, set the execution bit to the `knsk.sh` script and look at advanced options by typing `./knsk.sh --help`.

### Advanced options
    knsk.sh [options]

    --skip-tls            Set --insecure-skip-tls-verify on kubectl call
    --delete-api          Delete broken API founded in your Kubernetes cluster
    --delete-resource     Delete resources founded in your stucked namespaces
    --delete-all          Delete resources of stucked namespaces and broken API
    --force               Force deletion of stucked namespaces even if a clen deletion fail
    --port {number}       Up kubectl prosy on this port, default is 8765
    --timeout {number}    Max time (in seconds) to wait for Kubectl commands
    --no-color            All output without colors (useful for scripts)
    -h --help             Show this help
