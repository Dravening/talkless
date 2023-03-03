#!/usr/bin/env bash

# delete ks-install
kubectl delete deploy ks-installer -n d3os-system 2>/dev/null

# delete helm
for namespaces in d3os-system d3os-devops-system d3os-monitoring-system d3os-logging-system openpitrix-system d3os-monitoring-federated
do
  helm list -n $namespaces | grep -v NAME | awk '{print $1}' | sort -u | xargs -r -L1 helm uninstall -n $namespaces 2>/dev/null
done

# delete kubefed
kubectl get cc -n d3os-system ks-installer -o jsonpath="{.status.multicluster}" | grep enable
if [[ $? -eq 0 ]]; then
  helm uninstall -n kube-federation-system kubefed 2>/dev/null
  #kubectl delete ns kube-federation-system 2>/dev/null
fi


helm uninstall -n kube-system snapshot-controller 2>/dev/null

# delete d3os deployment
kubectl delete deployment -n d3os-system `kubectl get deployment -n d3os-system -o jsonpath="{.items[*].metadata.name}"` 2>/dev/null

# delete monitor statefulset
kubectl delete prometheus -n d3os-monitoring-system k8s 2>/dev/null
kubectl delete statefulset -n d3os-monitoring-system `kubectl get statefulset -n d3os-monitoring-system -o jsonpath="{.items[*].metadata.name}"` 2>/dev/null
# delete grafana
kubectl delete deployment -n d3os-monitoring-system grafana 2>/dev/null
kubectl --no-headers=true get pvc -n d3os-monitoring-system -o custom-columns=:metadata.namespace,:metadata.name | grep -E d3os-monitoring-system | xargs -n2 kubectl delete pvc -n 2>/dev/null

# delete pvc
pvcs="d3os-system|openpitrix-system|d3os-devops-system|d3os-logging-system"
kubectl --no-headers=true get pvc --all-namespaces -o custom-columns=:metadata.namespace,:metadata.name | grep -E $pvcs | xargs -n2 kubectl delete pvc -n 2>/dev/null


# delete rolebindings
delete_role_bindings() {
  for rolebinding in `kubectl -n $1 get rolebindings -l iam.d3os.io/user-ref -o jsonpath="{.items[*].metadata.name}"`
  do
    kubectl -n $1 delete rolebinding $rolebinding 2>/dev/null
  done
}

# delete roles
delete_roles() {
  kubectl -n $1 delete role admin 2>/dev/null
  kubectl -n $1 delete role operator 2>/dev/null
  kubectl -n $1 delete role viewer 2>/dev/null
  for role in `kubectl -n $1 get roles -l iam.d3os.io/role-template -o jsonpath="{.items[*].metadata.name}"`
  do
    kubectl -n $1 delete role $role 2>/dev/null
  done
}

# remove useless labels and finalizers
for ns in `kubectl get ns -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl label ns $ns d3os.io/workspace-
  kubectl label ns $ns d3os.io/namespace-
  kubectl patch ns $ns -p '{"metadata":{"finalizers":null,"ownerReferences":null}}'
  delete_role_bindings $ns
  delete_roles $ns
done

# delete clusters
for cluster in `kubectl get clusters -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch cluster $cluster -p '{"metadata":{"finalizers":null}}' --type=merge
done
kubectl delete clusters --all 2>/dev/null

# delete workspaces
for ws in `kubectl get workspaces -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch workspace $ws -p '{"metadata":{"finalizers":null}}' --type=merge
done
kubectl delete workspaces --all 2>/dev/null

# delete devopsprojects
for devopsproject in `kubectl get devopsprojects -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch devopsprojects $devopsproject -p '{"metadata":{"finalizers":null}}' --type=merge
done

for pip in `kubectl get pipeline -A -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch pipeline $pip -n `kubectl get pipeline -A | grep $pip | awk '{print $1}'` -p '{"metadata":{"finalizers":null}}' --type=merge
done

for s2ibinaries in `kubectl get s2ibinaries -A -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch s2ibinaries $s2ibinaries -n `kubectl get s2ibinaries -A | grep $s2ibinaries | awk '{print $1}'` -p '{"metadata":{"finalizers":null}}' --type=merge
done

for s2ibuilders in `kubectl get s2ibuilders -A -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch s2ibuilders $s2ibuilders -n `kubectl get s2ibuilders -A | grep $s2ibuilders | awk '{print $1}'` -p '{"metadata":{"finalizers":null}}' --type=merge
done

for s2ibuildertemplates in `kubectl get s2ibuildertemplates -A -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch s2ibuildertemplates $s2ibuildertemplates -n `kubectl get s2ibuildertemplates -A | grep $s2ibuildertemplates | awk '{print $1}'` -p '{"metadata":{"finalizers":null}}' --type=merge
done

for s2iruns in `kubectl get s2iruns -A -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch s2iruns $s2iruns -n `kubectl get s2iruns -A | grep $s2iruns | awk '{print $1}'` -p '{"metadata":{"finalizers":null}}' --type=merge
done

kubectl delete devopsprojects --all 2>/dev/null


# delete validatingwebhookconfigurations
for webhook in ks-events-admission-validate users.iam.d3os.io network.d3os.io validating-webhook-configuration
do
  kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io $webhook 2>/dev/null
done

# delete mutatingwebhookconfigurations
for webhook in ks-events-admission-mutate logsidecar-injector-admission-mutate mutating-webhook-configuration
do
  kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io $webhook 2>/dev/null
done

# delete users
for user in `kubectl get users -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch user $user -p '{"metadata":{"finalizers":null}}' --type=merge
done
kubectl delete users --all 2>/dev/null


# delete helm resources
for resource_type in `echo helmcategories helmapplications helmapplicationversions helmrepos helmreleases`; do
  for resource_name in `kubectl get ${resource_type}.application.d3os.io -o jsonpath="{.items[*].metadata.name}"`; do
    kubectl patch ${resource_type}.application.d3os.io ${resource_name} -p '{"metadata":{"finalizers":null}}' --type=merge
  done
  kubectl delete ${resource_type}.application.d3os.io --all 2>/dev/null
done

# delete workspacetemplates
for workspacetemplate in `kubectl get workspacetemplates.tenant.d3os.io -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch workspacetemplates.tenant.d3os.io $workspacetemplate -p '{"metadata":{"finalizers":null}}' --type=merge
done
kubectl delete workspacetemplates.tenant.d3os.io --all 2>/dev/null

# delete federatednamespaces in namespace d3os-monitoring-federated
for resource in $(kubectl get federatednamespaces.types.kubefed.io -n d3os-monitoring-federated -oname); do
  kubectl patch "${resource}" -p '{"metadata":{"finalizers":null}}' --type=merge -n d3os-monitoring-federated
done

# delete crds
for crd in `kubectl get crds -o jsonpath="{.items[*].metadata.name}"`
do
  if [[ $crd == *d3os.io ]]; then kubectl delete crd $crd 2>/dev/null; fi
done

# delete relevance ns
for ns in d3os-alerting-system d3os-controls-system d3os-devops-system d3os-logging-system d3os-monitoring-system d3os-monitoring-federated openpitrix-system d3os-system
do
  kubectl delete ns $ns 2>/dev/null
done