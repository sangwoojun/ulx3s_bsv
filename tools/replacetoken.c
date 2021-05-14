#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int
main(int argc, char** argv) {
	int paircnt = (argc-1)/2;
	char** fromtokens = (char**)malloc(paircnt*sizeof(char*));
	char** totokens = (char**)malloc(paircnt*sizeof(char*));
	for ( int i = 0; i < (argc-1)/2; i++ ) {
		fromtokens[i] = argv[1+i*2];
		totokens[i] = argv[2+i*2];
	}

	size_t rbufsz = 8192;
	char* rbf = (char*)malloc(sizeof(char)*rbufsz);
	size_t tbufsz = 8192;
	char* tbf = (char*)malloc(sizeof(char)*tbufsz);

	while(!feof(stdin)) {
		if ( getline(&rbf, &rbufsz, stdin) < 0 ) break;

		for ( int i = 0; i < paircnt; i++ ) {
			char* pf = strstr(rbf, fromtokens[i]);
			if ( !pf ) continue;

			//printf( ">> %s", rbf );
			if (strlen(rbf) + strlen(totokens[i]) - strlen(fromtokens[i]) >= rbufsz) {
				size_t newdiff = strlen(totokens[i]) - strlen(fromtokens[i]);
				rbf = (char*)realloc(rbf, rbufsz+newdiff);
				rbufsz += newdiff;
			}
			if (rbufsz != tbufsz) {
				tbf = (char*)realloc(tbf, rbufsz);
				tbufsz = rbufsz;
			}

			int offset = pf-rbf;
			strncpy(tbf, rbf, offset);

			strcpy(tbf+offset + strlen(totokens[i]), pf + strlen(fromtokens[i]));
			strncpy(tbf+offset, totokens[i], strlen(totokens[i]));
			strcpy(rbf,tbf);
			//printf( "<< %s", tbf );
		}
		printf( "%s", rbf );

	}
	
	return 0;
}
