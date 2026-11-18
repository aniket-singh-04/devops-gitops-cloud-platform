import fs from "node:fs";
import app from "./app.js";
import connectDB from "./db.js";

// Automatically load environment variables from .env file if present (Node.js 20+)
if (fs.existsSync(".env") && typeof process.loadEnvFile === "function") {
    process.loadEnvFile(".env");
}

const PORT = process.env.PORT || 4444;

// Connect to MongoDB Atlas and start HTTP server
const startServer = async () => {
    try {
        await connectDB();
        app.listen(PORT, () => {
            console.log(`Server is running at port ${PORT}`);
        });
    } catch (error) {
        console.error("Failed to start server:", error);
        process.exit(1);
    }
};

startServer();
