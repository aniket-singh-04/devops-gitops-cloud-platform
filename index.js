import app from "./app.js";
import connectDB from "./db.js";

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
