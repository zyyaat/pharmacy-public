package main
import ("context";"fmt";"os"
 "github.com/jackc/pgx/v5")
func main(){conn,err:=pgx.Connect(context.Background(),os.Getenv("DATABASE_URL"))
if err!=nil{fmt.Println("CONNECT_FAIL:",err);os.Exit(1)}
defer conn.Close(context.Background())
for _,s:=range os.Args[1:]{if _,err:=conn.Exec(context.Background(),s);err!=nil{fmt.Println("SQL_FAIL:",err);os.Exit(1)}}
fmt.Println("SQL_OK")}