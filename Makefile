build:
	odin build ./src -out:renderer -debug -vet-unused
run:
	odin run ./src -out:renderer -debug -vet-unused
build_release:
	odin build ./src -out:renderer -o:speed -vet-unused
run_release:
	odin run ./src -out:renderer -o:speed -vet-unused
