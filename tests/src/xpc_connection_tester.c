//
//  xpc_connection_tester.c
//  "Mac, Where's My Bootstrap"
//
//  Created by Csaba Fitzl
//


#include <stdio.h>
#include <stdlib.h>
#include <xpc/xpc.h>

int main(int argc, char **argv) {

	if (argc < 2) {
		printf("\n[-] XPC Service Name is missing\n\nUsage:\n\txpc_connection_tester <xpc_service_name>\n");
		exit(-1);
	}
	
	xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);	
	
	xpc_connection_t conn = xpc_connection_create_mach_service(argv[1], NULL, 0);
	if (conn == NULL) {
		perror("xpc_connection_create_mach_service");
	}
	
	xpc_connection_set_event_handler(conn, ^(xpc_object_t obj) {
		printf("Received message in generic event handler: %p\n", obj);
		printf("%s\n", xpc_copy_description(obj));
	});

	xpc_connection_resume(conn);

	// xpc_connection_send_message(conn, msg);

	return 0;
}
