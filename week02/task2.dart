class Student {
  // Fields
  String name;
  int id;
  List<double> grades;

  // Constructor
  Student(this.name, this.id, this.grades);

  // Calculate the average of the grades
  double calculateGPA() {
    if (grades.isEmpty) {
      return 0.0;
    }

    double total = 0.0;

    for (double grade in grades) {
      total += grade;
    }

    return total / grades.length;
  }
}

void main() {
  Student student = Student(
    'Lance',
    101,
    [3.5, 4.0, 3.0, 3.8],
  );

  print("Student: " + student.name);
  print("ID: " + student.id.toString());
  print("GPA: " + student.calculateGPA().toString());
}
