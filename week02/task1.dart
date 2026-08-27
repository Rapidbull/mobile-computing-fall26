double average(List<int> values) {
  double total = 0;
  values.forEach((values) => total += values);
  return total/(values.length);
}

void main() {
  print(average([10, 20 ,30])); //should print 20.2
}