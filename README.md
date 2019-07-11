# Containerised ADF Self-Hosted Integration Runtimes
 
Servian - Competitive Advantage through Data
 
jack.latrobe@servian.com


## Introduction 
This project works to make a highly-available, containerised deployment of the Azure Data Factory Self-Hosted Integration Runtime.
 
In summary, the Integration Runtime is a concept used by Azure Data Factory to move data and perform actions against sources that a public PaaS, cloud-based IR could not, such as on-prem databases or service endpointed storage. 
 
Previously, the IR needed to be run on a full-sized VM, and had a rather manual configuration process.
However, with recent work, the ADF team have made it possible to containerise this solution.
 
## Getting Started
You'll need to be running Docker for Windows, as the SHIR relies on the use of a windows container:
https://docs.docker.com/docker-for-windows/
 
(Obviously, more advanced users will look to configure a service such as AKS to host this moving forward)

## TODO
 - Assemble a build pipeline
 - Continuously deploy to ACR / AKS
 - Fix registration of HA nodes