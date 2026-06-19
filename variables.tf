variable "location" {
  default = "australiaeast"
}




variable "spokes" {
  type = map(object({
    address_space   = list(string)   # change from string to list(string)
    subnet_prefixes = list(string)
    subnet_names    = list(string)
  }))

  default = {
    spoke1 = {
      address_space   = ["10.0.0.0/16"]   # wrap in brackets
      subnet_prefixes = ["10.0.1.0/24", "10.0.2.0/24"]
      subnet_names    = ["identity-subnet", "vm-subnet"]
    }
    spoke2 = {
      address_space   = ["10.1.0.0/16"]   # wrap in brackets
      subnet_prefixes = ["10.1.1.0/24"]
      subnet_names    = ["workload-subnet"]
    }
  }
}