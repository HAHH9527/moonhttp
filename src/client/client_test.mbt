///|
test "placeholder" {
  if @client.placeholder() == false {
    fail("占位实现应返回 true")
  }
}
