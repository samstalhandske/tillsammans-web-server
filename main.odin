#+feature dynamic-literals
package main

import "core:log"
import "core:fmt"
import "core:os"
import "core:strings"

import tsm "tillsammans/server"

Server_Data :: struct {
	// ..
}

main :: proc() {
	server, create_server_result := tsm.create_server(tsm.Specification(Server_Data) {
		name = "web_server",
		protocol = .TCP,
		ip = "0.0.0.0",
		port = 7000,
		tickrate = 1,
		tick_mode = .Only_When_Has_Connections,
		max_connections = 512,

		commands = {
			"help" = proc(s: ^tsm.Server(Server_Data), args: []string) -> tsm.Command_Result {
				fmt.printfln("This is the help text!")

				fmt.printfln("There are %v commands available:", len(s.commands))
				for cmd in s.commands {
					fmt.printfln("'%v'", cmd)
				}
				return .OK
			},
			"stop" = proc(s: ^tsm.Server(Server_Data), args: []string) -> tsm.Command_Result {
				s.should_stop = true
				return .OK
			},
			"clients" = proc(s: ^tsm.Server(Server_Data), args: []string) -> tsm.Command_Result {
				fmt.printfln("There are %v connections:", len(s.connection_map))
				for connection_id, connection in s.connection_map {
					fmt.printfln("- Connection ID: %v, %#v.", connection_id, connection)
				}

				return .OK
			},
		},

		server_created_callback = proc(s: ^tsm.Server(Server_Data)) {
			fmt.printfln("Web-server: Created.")
		},
		server_started_callback = proc(s: ^tsm.Server(Server_Data)) {
			fmt.printfln("Web-server: Started.")
		},
		server_stopped_callback = proc(s: ^tsm.Server(Server_Data)) {
			fmt.printfln("Web-server: Stopped.")
		},
		server_received_bytes_callback = proc(s: ^tsm.Server(Server_Data), connection_id: tsm.Connection_ID, bytes: []u8) {
			fmt.printfln("Web-server: Received %v bytes from connection-id %v: %v", len(bytes), connection_id, bytes)

            fmt.printfln(string(bytes))

            recv_split := strings.split(string(bytes), "\r\n")
            defer delete(recv_split)

            request_start := strings.split(recv_split[0], " ")
            defer delete(request_start)
            action  := request_start[0]
            path    := request_start[1]
            version := request_start[2]

            // TODO: SS - Parse headers.
            // for header_row in recv_split[1:] {
            //     if header_row == "\r\n" {
            //         break
            //     }
            // }

            header := "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: %v\r\n\r\n%v"

            html := ""
            switch path[1:] {
                case "index", "": {
                    html = string(#load("index.html"))
                }
                case "about": {
                    html = string(#load("about.html"))
                }
                case: {
                    html = string(#load("error.html"))
                }
            }
            
            http_response := fmt.tprintf(header, len(html), html)
            tsm.send_bytes_to_connection_id(s, connection_id, transmute([]u8)http_response)
		},
		server_tick_callback = proc(s: ^tsm.Server(Server_Data), tick: tsm.Tick) {
		},
		server_connection_joined = proc(s: ^tsm.Server(Server_Data), connection_id: tsm.Connection_ID) {
		},
	})
	if create_server_result != .OK {
		fmt.eprintfln("Failed to initialize Web-server, result: %v.", create_server_result)
		return
	}

	defer {
		tsm.destroy_server(server)
		server  = nil
	}

	start_game_server_result := tsm.start_server(server)
	if start_game_server_result != .OK {
		fmt.eprintfln("Failed to start Web-server, result: %v.", start_game_server_result)
		return
	}

	defer tsm.stop_server(server)

	for tsm.server_alive(server) {
		buf: [256]byte
		n, err := os.read(os.stdin, buf[:])
		n -= 1 // Remove newline.
		if err != nil || n == 0 {
			continue
		}

		tsm.try_run_command(server, string(buf[:n]))
	}
}