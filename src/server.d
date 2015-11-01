module dmud.server;

import std.concurrency;
import std.socket;
import std.stdio;

import dmud.player;
import dmud.telnet_socket;

const SockOption_ReusePort = cast(SocketOption)15;

class Server {
	private {
		Socket ip4;
		Socket ip6;
	}
	
	bool stopping = false;
	
	this(ushort port) {
		ip4 = new TcpSocket(AddressFamily.INET);
		ip4.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
		ip4.setOption(SocketOptionLevel.SOCKET, SockOption_ReusePort, 1);
		ip4.bind(new InternetAddress(InternetAddress.ADDR_ANY, port));
		ip4.blocking = false;
		ip4.listen(10);
		
		ip6 = new TcpSocket(AddressFamily.INET6);
		ip6.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
		//ip6.setOption(SocketOptionLevel.SOCKET, SockOption_ReusePort, 1);
		ip6.bind(new Internet6Address(Internet6Address.ADDR_ANY, cast(ushort)(port + 1)));
		ip6.blocking = false;
		ip6.listen(10);
		
		scheduler.spawn({
			while (!stopping) {
				try {
					auto sock = ip4.accept();
					if (sock) {
						startNewConnection(sock);
					}
				} catch (SocketAcceptException e) {
					// Nothing to do here, move along.
				}
				try {
					auto sock = ip6.accept();
					if (sock) {
						startNewConnection(sock);
					}
				} catch (SocketAcceptException e) {
					// Nothing to do here, move along.
				}
				scheduler.yield();
			}
		});
	}
	
	void startNewConnection(Socket sock) {
		auto telnet = new TelnetSocket(sock);
		auto input = new WelcomeProcessor();
		input.run(telnet);
		scheduler.spawn(&telnet.run);
	}
}