// Package jobs handles background job processing using River Queue
//
// This package will contain:
// - Worker registration and configuration
// - Job clients for inserting new jobs
// - River Queue initialization and management
//
// All background jobs use PostgreSQL via River (no Redis/Kafka)

package jobs

// Workers holds all registered River workers
// TODO: Initialize and register all workers in Task N (Background Jobs)
var Workers []interface{} = nil

// InitWorkers initializes the River worker client
// TODO: Implement with proper River configuration
func InitWorkers() {
	// Placeholder - will connect to database and register workers
	// Example:
	// workers := []river.Worker{}
	// workers = append(workers, &ExpiryCheckerWorker{})
	// workers = append(workers, &LowStockCheckerWorker{})
	// workers = append(workers, &NotificationSenderWorker{})
}

// InsertJob adds a new job to the queue
// TODO: Implement job insertion with proper parameters
func InsertJob(jobType string, args interface{}) error {
	// Placeholder - will use river.Client.Insert
	_ = jobType
	_ = args
	return nil
}
