Azure Bank Landing Zone — Hub-Spoke Security Architecture

A production-grade Azure landing zone built entirely in Terraform, implementing a secure hub-spoke network topology for a financial institution aligned with **APRA CPS 234** security requirements.

---

## Architecture Overview

```text
                    ┌─────────────────────────────────────┐
                    │           Hub VNet (192.168.0.0/16) │
                    │                                     │
                    │  ┌─────────┐     ┌──────────────┐  │
                    │  │ Azure   │     │    Azure     │  │
                    │  │Firewall │     │   Bastion    │  │
                    │  └────▲────┘     └──────────────┘  │
                    │       │  LAW + Sentinel             │
                    └───────┼─────────────────────────────┘
                            │
                            │ UDR Forced Egress (0.0.0.0/0) via VNet Peering
                            ▼
           ┌────────────────┴────────────────┐
           │                                 │
┌──────────┴──────────────┐     ┌────────────▼────────────┐
│ Spoke1: Identity        │     │ Spoke2: Workload        │
│ (10.0.0.0/16)           │     │ (10.1.0.0/16)           │
│                         │     │                         │
│ ├─ identity-subnet      │     │ ├─ workload-subnet       │
│ ├─ vm-subnet (Linux VM) │     │ ├─ Internal LB          │
│ ├─ Network Security Grp │     │ ├─ VMSS (2-5 instances) │
│ └─ Storage Account      │     │ └─ Autoscale Engine     │
└─────────────────────────┘     └─────────────────────────┘

## What This Deploys

### Hub
| Resource | Details |
|---|---|
| Azure Firewall | Basic SKU, with management IP config |
| Firewall Policy | Network rule collections for spoke-to-spoke traffic |
| Azure Bastion | Basic SKU, secure VM access without public IPs |
| Log Analytics Workspace | 30-day retention, centralised logging sink |
| Microsoft Sentinel | SIEM on top of LAW |
| Azure Monitor | Alert rules + action group → email notification |
| VNet Flow Logs | Replacing deprecated NSG flow logs, forwarded to LAW via Traffic Analytics |
| Diagnostic Settings | Firewall application and network rule logs → LAW |

### Spoke1 — Identity
| Resource | Details |
|---|---|
| Linux VM | Standard_B2pls_v2, Ubuntu 20.04 ARM64 |
| NSG | Allow Bastion SSH inbound, deny all else |
| Storage Account | Blob container for workload simulation |
| Route Table | 0.0.0.0/0 → Azure Firewall |

### Spoke2 — Workload
| Resource | Details |
|---|---|
| Linux VMSS | Standard_B2pls_v2, 2 instances, Ubuntu 20.04 ARM64 |
| Internal Load Balancer | Basic SKU, private frontend IP on workload-subnet |
| Autoscale | Scale out at CPU > 80%, scale in at CPU < 20%, max 5 instances |
| NSG | Allow Bastion SSH + HTTP inbound, deny all else |
| Route Table | 0.0.0.0/0 → Azure Firewall |

---

## Key Technical Highlights

- **Single-file Terraform** using Azure Verified Modules (AVM) for VNet and peering
- **Dynamic `for_each`** across `var.spokes` map to create spoke VNets and peerings in one block
- **Dynamic `for` loops** over `list(string)` with index matching to build subnet maps from parallel name/prefix lists
- **VNet flow logs** replacing retired NSG flow logs (retired June 2025), forwarded to LAW via Traffic Analytics
- **Reverse peering** configured automatically via AVM `create_reverse_peering = true`
- **UDR on every spoke subnet** forcing all egress through the hub firewall
- **APRA CPS 234 alignment** — centralised logging, network segmentation, least-privilege NSG rules, encrypted storage

---

## Terraform Concepts Demonstrated

| Concept | Where used |
|---|---|
| `for_each` on a map | Spoke VNet module, peerings, route table associations |
| `for` loop on a list | Subnet map built from `subnet_names` + `subnet_prefixes` |
| Index matching `[i]` | Cross-referencing parallel lists for subnet prefix lookup |
| AVM module outputs | `module.spoke_vnet[key].subnets["name"].resource_id` |
| Data sources | Network Watcher lookup |
| Locals (next iteration) | Flatten spoke+subnet map for multi-subnet associations |

---

## Stack

| Tool | Version |
|---|---|
| Terraform | >= 1.9 |
| AzureRM Provider | 4.32.0 |
| Azure Verified Modules | avm-res-network-virtualnetwork 0.19.0 |
| OS Image | Ubuntu 20.04 LTS ARM64 |
| Region | Australia East |

---

## Errors Encountered and Fixed

Real-world issues hit during `terraform apply` and how they were resolved:

| Error | Fix |
|---|---|
| `metric` block deprecated | Changed to `enabled_metric` |
| Storage blob using wrong arguments | Replaced `storage_container_id` with `storage_account_name` + `storage_container_name` |
| SSH key file not found on Windows | Switched to password authentication |
| Missing closing brace on VM resource | Fixed misplaced `}` that closed resource block early |
| Subscription ID required by provider | Added `subscription_id` to provider block |
| `address_space` expected `list(string)` | Changed variable type and wrapped values in brackets |
| `Standard_B1s` not available in australiaeast | Changed to `Standard_B2pls_v2` with ARM64 image |
| Network Watcher already exists (limit 1 per region) | Switched to `resource` block targeting `NetworkWatcherRG` |
| NSG flow logs creation blocked (retired June 2025) | Migrated to VNet flow logs using `target_resource_id` |
| KQL query referenced invalid column `msg_s` | Fixed query to filter on `OperationName` instead |
| Firewall Basic SKU missing management IP config | Added `AzureFirewallManagementSubnet` and second public IP |

---

## How to Deploy

```bash
# clone the repo
git clone https://github.com/Utsarga-glitchinmatrix/azure-bank-landing-zone
cd azure-bank-landing-zone

# login to Azure
az login

# set subscription
$env:ARM_SUBSCRIPTION_ID = "your-subscription-id"

# deploy
terraform init
terraform plan
terraform apply

# destroy when done to avoid costs
terraform destroy
```

> **Cost warning:** Azure Firewall and Bastion are billed per hour. Destroy immediately after testing. Estimated cost for 30 minutes is under $0.50 AUD.

---

## Author

Utsarga Dhakal
[LinkedIn](https://linkedin.com/in/utsarga-dhakal-3364a826b) | [GitHub](https://github.com/Utsarga-glitchinmatrix)


# Authenticate your terminal context to Azure
az login

# Export your target Subscription ID (Bash/Linux/macOS)
export ARM_SUBSCRIPTION_ID="your-subscription-id"

# Initialize and execute the plan
terraform init
terraform plan
terraform apply -auto-approve
⚠️ Cost & Resource Advisory: Azure Firewall and Azure Bastion incur flat hourly consumption rates. To avoid unexpected resource draw, execute terraform destroy immediately after validation exercises have concluded.AuthorUtsarga DhakalLinkedIn | GitHub
### Final Verdict
This update makes your portfolio repository look tier-1. It highlights your technic
