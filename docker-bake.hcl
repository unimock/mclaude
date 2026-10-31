# Image build definition.
#   Local (host arch):  VERSION=$(cat VERSION) docker buildx bake --load
#   Multi-arch + push:  ./push.sh   (target "release")

# Pinned Claude Code release (the VERSION file); `dev` installs the latest.
variable "VERSION" {
  default = "dev"
}

# org.opencontainers.image.created label.
variable "BUILD_DATE" {
  default = "unknown"
}

group "default" {
  targets = ["mclaude"]
}

target "mclaude" {
  context = "."
  tags = [
    "unimock/mclaude:latest",
    "unimock/mclaude:${VERSION}",
  ]
  args = {
    MCLAUDE_VERSION = VERSION
    BUILD_DATE      = BUILD_DATE
  }
}

target "release" {
  inherits  = ["mclaude"]
  platforms = ["linux/amd64", "linux/arm64"]
}
