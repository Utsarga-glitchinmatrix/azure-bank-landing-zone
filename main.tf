terraform {
  required_version = ">= 1.0.0" # Ensure that the Terraform version is 1.0.0 or higher

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.32.0"
    }


  }

}

provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "Bank_Hub" {
  location=var.location
  name="Bank-Hub-RG"
}