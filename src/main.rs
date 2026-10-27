#[tokio::main]
async fn main() {
    if let Err(error) = opencode_proxy::run().await {
        eprintln!("{error}");
        std::process::exit(2);
    }
}
