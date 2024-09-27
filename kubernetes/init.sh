#!/usr/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'

apply_crd_if_missing() {
	CRD=$1
	URL=$2
	if kubectl get crd "$CRD" >/dev/null 2>&1; then
		echo -e "$CRD already exists, skipping..."
	else
		echo -e "Applying CRD $CRD"
		kubectl apply --server-side -f "$URL"
	fi
}

echo ""
echo -e "${GREEN}DEPLOYING LONGHORN${NC}"
helmfile apply --wait -f helmfile/longhorn.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING NFS CSI AND NFS STORAGECLASS${NC}"
echo ""
helmfile apply --wait -f helmfile/nfscsi.yaml
kubectl apply -f kustomize/kube-system/nfs-storageclass.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING METALLB${NC}"
echo ""
helmfile apply --wait -f helmfile/metallb.yaml
kubectl apply -f kustomize/metallb/pool.yaml
kubectl apply -f kustomize/metallb/advert.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING TRAEFIK${NC}"
echo ""
helmfile apply --wait -f helmfile/traefik.yaml
kubectl apply -f kustomize/traefik/default-headers.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING CERTMANAGER${NC}"
echo ""
helmfile apply --wait -f helmfile/certmanager.yaml
kubectl apply -f kustomize/certmanager/cf-token.yaml
kubectl apply -f kustomize/certmanager/clusterissuer.yaml
kubectl apply -f kustomize/certmanager/default-cert.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING PIHOLE AND EXTERNALDNS FOR PIHOLE${NC}"
echo ""
helmfile apply --wait -f helmfile/pihole.yaml
kubectl apply -f kustomize/pihole/credentials.yaml
helmfile apply --wait -f helmfile/externaldns.yaml
echo ""
echo ""

echo -e "${GREEN}DEPLOYING MONITORING STACK${NC}"
echo ""

apply_crd_if_missing "alertmanagerconfigs.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml"
apply_crd_if_missing "alertmanagers.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml"
apply_crd_if_missing "podmonitors.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml"
apply_crd_if_missing "probes.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_probes.yaml"
apply_crd_if_missing "prometheusagents.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusagents.yaml"
apply_crd_if_missing "prometheuses.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml"
apply_crd_if_missing "prometheusrules.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml"
apply_crd_if_missing "scrapeconfigs.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml"
apply_crd_if_missing "servicemonitors.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml"
apply_crd_if_missing "thanosrulers.monitoring.coreos.com" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml"

kubectl apply -f kustomize/monitoring/cert.yaml
kubectl apply -f kustomize/monitoring/credentials.yaml
helmfile apply --wait -f helmfile/monitoring.yaml
kubectl apply -f kustomize/monitoring/ingress.yaml
echo ""
echo ""
