.text
addi t1, zero, 1024
la t0, testdata
lw s1, 0(t0)
lw s2, 4(t0)
add s3, s1, s2
sw s3, 0(t1)
unimp


.data
testdata:
.word 1, 2, 3
