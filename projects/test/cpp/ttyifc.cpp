#include "ttyifc.h"

void set_tty_attributes(int fd, int baud)
{
	struct termios tty;
	if (tcgetattr(fd, &tty) < 0) {
		printf("tcgetattr error: %s\n", strerror(errno));
		return;
	}

	cfsetospeed(&tty, (speed_t)baud);
	cfsetispeed(&tty, (speed_t)baud);

	tty.c_cflag |= (CLOCAL | CREAD);
	tty.c_cflag &= ~CSIZE;
	tty.c_cflag |= CS8;
	tty.c_cflag &= ~PARENB; // no parity bit
	tty.c_cflag &= ~CSTOPB; // 1 stop bit
	tty.c_cflag &= ~CRTSCTS; // no flow control

	tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
	tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

	tty.c_oflag &= ~OPOST;

	tty.c_cc[VMIN] = 1;
	tty.c_cc[VTIME] = 1;

	if (tcsetattr(fd, TCSANOW, &tty) != 0) {
		printf("tcsetattr error: %s\n", strerror(errno));
	}
	return;
}
