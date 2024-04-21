build:
	odin build ./src -out:renderer -o:speed
run:
	odin run ./src -out:renderer -o:speed
check:
	odin check ./src -vet-unused
