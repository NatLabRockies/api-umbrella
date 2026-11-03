use std::env;
use std::fs;
use std::os::unix::process::CommandExt;
use std::process::Command;

// A minimal binary that writes the Envoy config file based on YAML in an
// environment variable, and then replaces the process with the real envoy
// process (passing all arguments along).
//
// The driver of this is to have a statically compiled binary that will work in
// our "distroless" envoy egress image in a way that makes it easier to
// integrate our configuration from environment variables in Cloud Foundry
// (since it can't mount files into the container).
fn main() {
    let config_yaml = env::var("ENVOY_CONFIG_YAML");
    if config_yaml.is_ok() {
        fs::write("/etc/envoy/envoy.yaml", config_yaml.unwrap())
            .expect("Error writing '/etc/envoy/envoy.yaml' file");
    }

    let config_yaml = env::var("FLUENT_BIT_CONFIG_YAML");
    if config_yaml.is_ok() {
        fs::write("/fluent-bit/etc/fluent-bit.yaml", config_yaml.unwrap())
            .expect("Error writing '/fluent-bit/etc/fluent-bit.yaml' file");
    }

    let args: Vec<_> = env::args_os().skip(1).collect();
    let err = Command::new(&args[0]).args(&args[1..]).exec();
    println!("Error: {}", err);
}
