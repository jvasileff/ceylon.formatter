void testIssue36() {
value max = 25;
value matches = zipEntries(
{ for (i in 2..max) if ((2 .. (i - 1)).every((Integer e) => i%e != 0)) i }, // primes
{ for (j in 1..max) (1..j).fold(1, (Integer a, Integer b) => a * b) + 1 } // factorials + 1
).filter((Integer->Integer e) => e.key == e.item);
}
