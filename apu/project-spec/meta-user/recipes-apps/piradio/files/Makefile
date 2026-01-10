APP = piradio

SRCS=$(wildcard *.c)
APP_OBJS = $(SRCS:.c=.o)

all: build

build: $(APP)

$(APP): $(APP_OBJS)
	$(CC) -o $@ $(APP_OBJS) $(LDFLAGS) $(LDLIBS)
clean:
	rm -f $(APP) *.o

