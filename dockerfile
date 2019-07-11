FROM mcr.microsoft.com/windows/servercore:ltsc2019
LABEL maintainer="jack.latrobe@servian.com"
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';"]
ADD shir.ps1 .
ADD RegisterIntegrationRuntimeNode.ps1 .
ADD IntegrationRuntime.msi .
CMD ["powershell", ".\\shir.ps1"]