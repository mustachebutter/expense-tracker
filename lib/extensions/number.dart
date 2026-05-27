extension ListMath<T> on List<T>
{
  double sumBy (double Function (T item) selector)
  {
    return fold(0.0, (sum, item) => sum + selector(item));
  }
}