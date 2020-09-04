package goRPC

import (
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/rpc"
)

type Args struct {
	A, B int
}

type Quotient struct {
	Quo, Rem int
}

type Math int

func (t *Math) Multiply(args *Args, reply *int) error {
	*reply = args.A * args.B
	return nil
}

func (t *Math) Divide(args *Args, quo *Quotient) error {
	if args.B == 0 {
		return errors.New("divide by zero")
	}

	quo.Quo = args.A / args.B
	quo.Rem = args.A % args.B
	return nil
}

func StartServer() {
	math := new(Math)
	rpc.Register(math)
	rpc.HandleHTTP()

	//http.ListenAndServe(":7080", nil)
	l, e := net.Listen("tcp", "127.0.0.1:7770")

	if e != nil {
		log.Fatal("listen error:", e)
	}
	http.Serve(l, nil)
}

func StartClient() {
	var reply int
	client, err := rpc.DialHTTP("tcp", "127.0.0.1"+":7770")
	if err != nil {
		log.Fatal("dialing:", err)
	}
	args := &Args{7, 8}
	err = client.Call("Math.Multiply", args, &reply)
	if err != nil {
		log.Fatal("math error:", err)
	}
	fmt.Printf("math: %d*%d=%d", args.A, args.B, reply)
}
