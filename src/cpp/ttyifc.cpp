#include "ttyifc.h"

pthread_mutex_t g_mutex;
pthread_t g_thread;
std::queue<uint8_t> sw2hwq;
std::queue<uint8_t> hw2swq;
void* swmain(void* param);

int tty_fd;

bool g_init_done = false;
void init() {
	if ( g_init_done ) return;
	pthread_mutex_init(&g_mutex, NULL);
	pthread_create(&g_thread, NULL, swmain, NULL);

	g_init_done = true;
}

uint8_t g_outidx = 0xff;
//extern "C" 
uint32_t bdpiUartGet(uint8_t idx) {
	init();

	uint32_t data = 0xffffffff;
	pthread_mutex_lock(&g_mutex);
	if ( idx != g_outidx && !sw2hwq.empty() ) {
		// get new data
		data = sw2hwq.front();
		sw2hwq.pop();
		//printf( "uart get %d %d %d -> %x\n", idx, g_outidx, sw2hwq.size(), data&0xff );
		g_outidx = ((int)g_outidx+1)&0xff;
	}
	pthread_mutex_unlock(&g_mutex);
	return data;
}

uint8_t g_inidx = 0xff;
//extern "C" 
void bdpiUartPut(uint32_t d) {
	init();

	uint8_t idx = 0xff&(d>>8);
	uint8_t data = 0xff&d;
	if ( idx != g_inidx ) {
		g_inidx = idx;
		//printf( "--%d, %d\n",idx, data );
		pthread_mutex_lock(&g_mutex);
		hw2swq.push(data);
		pthread_mutex_unlock(&g_mutex);
	}
}

uint32_t uart_recv() {
	uint32_t r = 0xffffffff;
#ifdef SYNTH
	uint32_t din = 0;
	int rdlen = read(tty_fd, &din, 1);
	if ( rdlen > 0 ) r = din;
	if ( rdlen > 1 ) printf( "received too many bytes from uart! %d\n", rdlen );
#else
	init();

	pthread_mutex_lock(&g_mutex);
	if ( !hw2swq.empty() ) {
		r = hw2swq.front();
		hw2swq.pop();
	}
	pthread_mutex_unlock(&g_mutex);
#endif
	return r;
}
void uart_send(uint8_t data) {
#ifdef SYNTH
	write(tty_fd, &data, sizeof(data));
	tcdrain(tty_fd);
#else
	init();

	pthread_mutex_lock(&g_mutex);
	sw2hwq.push(data);
	pthread_mutex_unlock(&g_mutex);
#endif
}

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

	tty.c_cc[VMIN] = 0;
	tty.c_cc[VTIME] = 0;

	if (tcsetattr(fd, TCSANOW, &tty) != 0) {
		printf("tcsetattr error: %s\n", strerror(errno));
	}
	return;
}
int open_tty(char* path){
	char* ttyname = path;
	tty_fd = open(ttyname, O_RDWR | O_NOCTTY | O_SYNC);
	if (tty_fd < 0) {
		printf("Error opening TTY %s (%s)\n", ttyname, strerror(errno));
		return 1;
	}
	set_tty_attributes(tty_fd, B115200);
	/* // not necessary since VMIN and VTIME set to zero...?
	int flags = fcntl(tty_fd, F_GETFL, 0);
	fcntl(tty_fd, F_SETFL, flags | O_NONBLOCK);
	*/
	return 0;
}
