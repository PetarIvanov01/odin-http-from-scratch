use actix_web::{App, HttpResponse, HttpServer, web};

async fn pong() -> HttpResponse {
    HttpResponse::Ok().body("Pong")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    println!("Rust server listening on http://127.0.0.1:8080");

    HttpServer::new(|| App::new().route("/pong", web::get().to(pong)))
        .bind(("127.0.0.1", 8080))?
        .run()
        .await
}
