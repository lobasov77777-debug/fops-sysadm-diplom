terraform {
  required_version = ">= 1.8.4"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.129.0"
    }
  }
}

provider "yandex" {
  folder_id = var.folder_id
  zone      = var.zones[0]
}
