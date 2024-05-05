build:
	odin build ./src -out:renderer -o:speed -show-timings
run:
	odin run ./src -out:renderer -o:speed -show-timings
check:
	odin check ./src -vet-unused
