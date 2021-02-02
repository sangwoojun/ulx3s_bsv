.text

# mult safe
addi t0, zero, 2
addi t1, zero, 3
addi t2, zero, 7
nop
nop
nop
nop
nop
mul t0, t0, t1
nop
nop
nop
nop
nop
add t1, t2, t1
nop
nop
nop
nop
nop
mul t0, t0, t1
nop
nop
nop
nop
nop
addi t3, zero, 1024
nop
nop
nop
nop
nop
sw t0, 0(t3)

# branch pipe safe
branch:

addi t0, zero, 1025
addi t1, zero, 3
addi t2, zero, 3
addi t3, zero, 0
nop
nop
nop
nop
nop
nop

beq t1, t2, skip

sw t3, 0(t0)
j multunsafe

skip:
sw t2, 0(t0)
#unimp

multunsafe:

# mult pipe unsafe
li t0, 2
li t1, 7
li t2, 17
li t3, 5
addi t2, t2, -4
mul t2, t1, t2 # 7*13=91
add t0, t3, t0 # 2+5=7
sub t0, t2, t0 # 91-7 = 84
addi t3, zero, 1026
sw t0, 0(t3)


# pip3 unsafe 2
addi t1, zero, 1027
la t0, testdata
lw s1, 0(t0)
lw s2, 4(t0)
add s3, s1, s2
sw s3, 0(t1)






unimp


.data
testdata:
.word 1, 2, 3



#branch1.s
#mult.s
#pipesafe.s
#pipeunsafe1.s
#pipeunsafe2.s
