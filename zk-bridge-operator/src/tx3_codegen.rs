use std::collections::HashMap;

pub use bridge_aiken_tx3_client as generated;

#[cfg_attr(not(test), allow(dead_code))]
pub const DEFAULT_LOCAL_TRP_ENDPOINT: &str = generated::DEFAULT_TRP_ENDPOINT;

#[cfg_attr(not(test), allow(dead_code))]
fn default_headers() -> HashMap<String, String> {
    generated::DEFAULT_HEADERS
        .iter()
        .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
        .collect()
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn client_for_trp_endpoint(endpoint: impl Into<String>) -> generated::Client {
    client_for_trp_endpoint_with_headers(endpoint, default_headers())
}

pub fn client_for_trp_endpoint_with_headers(
    endpoint: impl Into<String>,
    headers: HashMap<String, String>,
) -> generated::Client {
    generated::Client::new(generated::ClientOptions {
        endpoint: endpoint.into(),
        headers: Some(headers),
    })
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn default_local_client() -> generated::Client {
    generated::Client::with_default_options()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_client_keeps_local_baseline_endpoint() {
        assert_eq!(DEFAULT_LOCAL_TRP_ENDPOINT, "http://localhost:8164");
    }

    #[test]
    fn preview_ready_client_can_be_constructed_non_interactively() {
        let _client = client_for_trp_endpoint("http://127.0.0.1:6542");
    }

    #[test]
    fn default_local_client_can_be_constructed_non_interactively() {
        let _client = default_local_client();
    }
}
