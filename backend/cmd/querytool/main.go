package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	conn, err := pgx.Connect(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil { fmt.Println("CONNECT_FAIL:", err); os.Exit(1) }
	defer conn.Close(context.Background())
	rows, err := conn.Query(context.Background(), os.Args[1])
	if err != nil { fmt.Println("QUERY_FAIL:", err); os.Exit(1) }
	defer rows.Close()
	for rows.Next() {
		vals, _ := rows.Values()
		line := ""
		for _, v := range vals {
			line += fmt.Sprintf("%v | ", v)
		}
		fmt.Println(line)
	}
	if rows.Err() != nil { fmt.Println("ROWS_FAIL:", rows.Err()) }
}
