import express from "express";
import mongoose from "mongoose";

const app = express();

// Route 1: Server Information
app.get("/", (req, res) => {
    return res.status(200).json({
        success: true,
        message: "Welcome to the Express Server",
        server: "Express.js",
        database: mongoose.connection.readyState === 1 ? "Connected (MongoDB Atlas)" : "Disconnected",
        port: process.env.PORT || 4444,
        environment: process.env.NODE_ENV || "development"
    });
});

// Route 2: Health Check (used by Docker healthcheck & K8s liveness/readiness probes)
app.get("/health", (req, res) => {
    const dbState = mongoose.connection.readyState;
    const dbStatusMap = {
        0: "disconnected",
        1: "connected",
        2: "connecting",
        3: "disconnecting"
    };

    return res.status(200).json({
        success: true,
        status: "OK",
        database: dbStatusMap[dbState] || "unknown",
        message: "Server is healthy",
        uptime: process.uptime()
    });
});

export default app;
