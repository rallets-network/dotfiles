NAMESPACE=default
RUNNING_POD=""
LEFT_ARGS=""
KCONTEXT=""
function getpod {
  RAN=true
  function usage ()
  {
    echo "Usage :  $0 [options] [--]
    Options:
    -K            kubectl context
    -R            not randomly select pod
    -n NAMESPACE
    -p PROJECT
    -h            Display this message"
  }
  while getopts ":hvK:Rp:" opt
  do
    case $opt in
    R) RAN=false         ;;
    h) usage; return 0   ;;
    n) NAMESPACE=$OPTARG ;;
    p) PROJECT=$OPTARG   ;;
    K) KCONTEXT=$OPTARG  ;;
    *) echo -e "\n  Option does not exist: $OPTARG\n"
       usage; return 1   ;;
    esac
  done
  shift $(($OPTIND-1))

  RUNNING_POD_INDEX=-1
  while true; do
    echo "kubectl -n $NAMESPACE get pods | grep $PROJECT"
    ALL_PODS=$(kubectl -n $NAMESPACE get pods | grep "$PROJECT")
    echo $fg[green]"All Pods:"$reset_color
    echo $ALL_PODS
    if  [[ ${#ALL_PODS[@]} == 0 ]]; then
      echo $fg[red]"Pod not found for $PROJECT"$reset_color
      break
    fi
    RUNNING_PODS=($(echo $ALL_PODS | egrep "$PROJECT.* ?[1-9]/[0-9]? *Running" | awk '{print $1}'))
    if [[ `echo $ALL_PODS | wc -l` != ${#RUNNING_PODS[@]} ]]; then
      sleep 2
      echo $fg[red]'Pods are not ready, wait...'$reset_color
      continue
    fi
    if [[ ${#RUNNING_PODS[@]} == 0 ]]; then
      echo "Pod not found for $PROJECT"
      break
    fi
    if [[ $RAN == 'true' ]];then
      RUNNING_POD_INDEX=`shuf -i 1-${#RUNNING_PODS[@]} -n 1`
      break
    fi
    if [ ${#RUNNING_PODS[@]} -eq 1 ];then
      RUNNING_POD_INDEX=1
      break
    elif [ ${#RUNNING_PODS[@]} -gt 1 ];then
      echo $fg[green]'Running Pods:'$reset_color
      INDEX=1
      for i in $RUNNING_PODS;do
        echo "[$INDEX] $i"
        let INDEX=${INDEX}+1
      done
      echo $fg[green]'Select option of pod to execute:'$reset_color
      while true;do
        read RUNNING_POD_INDEX
        if [[ $RUNNING_POD_INDEX -gt 0 && $RUNNING_POD_INDEX -le ${#RUNNING_PODS[@]} ]];then
          break
        else
          echo 'invalid option...'
        fi
      done
      break
    fi
  done
  RUNNING_POD=$RUNNING_PODS[$RUNNING_POD_INDEX]
  LEFT_ARGS=$@
}

function kexec {
  getpod $@
  if [[ $RUNNING_POD != "" ]]; then
    echo "kubectl -it -n $NAMESPACE exec $RUNNING_POD -- /bin/sh -c $LEFT_ARGS"
    kubectl -it -n $NAMESPACE exec $RUNNING_POD -- /bin/sh -c $LEFT_ARGS
  fi
}

function klogs {
  finalopts=()
  while [[ $@ != "" ]] do
    case $1 in
      --context=*)
        KCONTEXT="${i#*=}"
        shift
        ;;
      -p)
        PROJECT="$2"
        shift; shift
        ;;
      -i)
        INSTANCE="$2"
        shift; shift
        ;;
      *)
        finalopts+=($1)
        shift
        ;;
    esac
  done

  if [[ "$PROJECT" != "" ]]; then
    kubectl logs -f deployment/$PROJECT --all-containers=true --since=5s --pod-running-timeout=2s $finalopts
  elif  [[ "$INSTANCE" != "" ]]; then
    while true; do
      kubectl logs -f --max-log-requests=10 -l app.kubernetes.io/instance=$INSTANCE 1>&0
      echo "Waiting..."
      sleep 2
    done
  fi
}
function k_delete_evicted {
  k delete pod `k get pods | grep Evicted | awk '{print $1}'`
}
function k_get_instance {
  k get pods -o jsonpath="{.items[*].metadata.labels['app\.kubernetes\.io\/instance']}" | tr " " "\n" | uniq
}
function kubectl() {
  DEBUG=false
  finalopts=()
  while [[ $@ != "" ]] do
    case $1 in
      --context=*)
        KCONTEXT="${i#*=}"
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --)
        finalopts+=("$@")
        break
        ;;
      *)
        finalopts+=($1)
        shift
        ;;
    esac
  done
  [[ $DEBUG == "true" ]] && echo "kubectl --kubeconfig=$HOME/.kube/${KCONTEXT}_config $finalopts"
  command kubectl --kubeconfig=$HOME/.kube/${KCONTEXT}_config $finalopts
}