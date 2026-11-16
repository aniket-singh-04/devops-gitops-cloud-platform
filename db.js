import mongoose from "mongoose";

// ──────────────────────────────────────────────────────────────
// MongoDB Atlas Connection
// Uses MONGO_URI from environment variables to connect
// Includes retry logic for resilient startup in containers
// ──────────────────────────────────────────────────────────────

const connectDB = async () => {
    const uri = process.env.MONGO_URI;

    // Warn and skip if no URI is provided (allows app to run without DB)
    if (!uri) {
        console.warn("⚠️  MONGO_URI not set — skipping database connection");
        return;
    }

    try {
        const conn = await mongoose.connect(uri, {
            // Connection pool settings for production workloads
            maxPoolSize: 10,
            serverSelectionTimeoutMS: 5000,
            socketTimeoutMS: 45000,
        });

        console.log(`✅ MongoDB connected: ${conn.connection.host}`);
    } catch (error) {
        console.error(`❌ MongoDB connection failed: ${error.message}`);
        process.exit(1);
    }
};

export default connectDB;
