defmodule ElixirLS.LanguageServer.Providers.ExecuteCommand.ManipulatePipes.ASTTest do
  use ExUnit.Case

  alias ElixirLS.LanguageServer.Providers.ExecuteCommand.ManipulatePipes.AST

  describe "to_pipe/1" do
    test "treats macro.to_string escaping chars" do
      assert AST.to_pipe("String.split(text, ~r\"\\\"\\a\\\"\", trim: true)") ==
               {:ok, "text |> String.split(~r\"\\\"\\a\\\"\", trim: true)"}
    end

    test "single-line selection with two args in named function" do
      assert AST.to_pipe("X.Y.Z.function_name(A.B.C.a(), b)") ==
               {:ok, "A.B.C.a() |> X.Y.Z.function_name(b)"}
    end

    test "single-line selection with single arg in named function" do
      assert AST.to_pipe("X.Y.Z.function_name(A.B.C.a())") ==
               {:ok, "A.B.C.a() |> X.Y.Z.function_name()"}
    end

    test "single-line selection with two args in anonymous function" do
      assert AST.to_pipe("function_name.(A.B.C.a(), b)") ==
               {:ok, "A.B.C.a() |> function_name.(b)"}
    end

    test "single-line selection with single arg in anonymous function" do
      assert AST.to_pipe("function_name.(A.B.C.a())") == {:ok, "A.B.C.a() |> function_name.()"}
    end

    test "multi-line selection with two args in named function" do
      assert AST.to_pipe("""
               X.Y.Z.function_name(
               X.Y.Z.a(),
               b,
               c
             )
             """) == {:ok, "X.Y.Z.a() |> X.Y.Z.function_name(b, c)"}
    end

    test "multi-line with \r as separator and \r\n inside strings raises syntax error" do
      # This test shows that the parser is limited to Elixir's parser's capabilities
      assert {:error, :invalid_code} = AST.to_pipe(~s{X.Y.Z.function_name(\r1,\r"asdf\nghjk")})
    end

    test "on 0 arity function call" do
      assert AST.to_pipe("f.()") == {:ok, "f.()"}
      assert AST.to_pipe("f()") == {:ok, "f()"}
      assert AST.to_pipe("My.Nested.Module.f()") == {:ok, "My.Nested.Module.f()"}
    end

    test "on atom" do
      assert AST.to_pipe(":asdf") == {:ok, ":asdf"}
      assert AST.to_pipe("MyModule") == {:ok, "MyModule"}
    end

    test "calls with no parens" do
      assert AST.to_pipe("f 1, 2") == {:ok, "1 |> f(2)"}
      assert AST.to_pipe("MyModule.f 1, 2") == {:ok, "1 |> MyModule.f(2)"}
    end

    test "already a piped call (idempotency check)" do
      assert AST.to_pipe("1 |> f(2)") == {:ok, "1 |> f(2)"}
      assert AST.to_pipe("1 |> MyModule.f(2)") == {:ok, "1 |> MyModule.f(2)"}
      assert AST.to_pipe("1 |> g() |> MyModule.f(2)") == {:ok, "1 |> g() |> MyModule.f(2)"}
    end

    test "does not pipe operators" do
      assert AST.to_pipe("1 + 2") == {:ok, "1 + 2"}
      assert AST.to_pipe("+2") == {:ok, "+2"}
      # ensure that fully qualified operators are piped
      assert AST.to_pipe("Kernel.+(1, 2)") == {:ok, "1 |> Kernel.+(2)"}
    end
  end

  describe "from_pipe/1 single-line" do
    test "treats macro.to_string escaping chars" do
      assert AST.from_pipe("text |> String.split(~r\"\\a\", trim: true)") ==
               {:ok, "String.split(text, ~r\"\\a\", trim: true)"}
    end

    test "does not change code without pipes" do
      code = "f(a, b, c)"

      assert AST.from_pipe(code) == {:ok, code}
    end

    test "three args in named function" do
      piped = "a |> function_name(b, c) |> after_call"
      unpiped = "function_name(a, b, c) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "pipe chain" do
      piped = "a |> b() |> function_name(c, d) |> after_call"
      unpiped = "b(a) |> function_name(c, d) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "pipe chain with no raw start" do
      piped = "b(a) |> function_name(c, d) |> after_call"
      unpiped = "function_name(b(a), c, d) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in named function" do
      piped = "a |> function_name() |> after_call"
      unpiped = "function_name(a) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "three args in anonymous function" do
      piped = "a |> function_name.(b, c) |> after_call"
      unpiped = "function_name.(a, b, c) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in anonymous function" do
      piped = "a |> function_name.() |> after_call"
      unpiped = "function_name.(a) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "three args in named function and statement before call" do
      piped = "a |> function_name(b, c) |> after_call"
      unpiped = "function_name(a, b, c) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in named function and statement before call" do
      piped = "a |> function_name() |> after_call"
      unpiped = "function_name(a) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "three args in anonymous function and statement before call" do
      piped = "a |> function_name.(b, c) |> after_call"
      unpiped = "function_name.(a, b, c) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in anonymous function and statement before call" do
      piped = "a |> function_name.() |> after_call"
      unpiped = "function_name.(a) |> after_call"
      assert AST.from_pipe(piped) == {:ok, unpiped}
    end
  end

  describe "from_pipe/1 multi-line" do
    test "three args in named function" do
      piped = """
      a
      |> function_name(b, c)
      |> after_call
      """

      unpiped = "function_name(a, b, c) |> after_call"

      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in named function" do
      piped = """
      a
      |> function_name()
      |> after_call
      """

      unpiped = "function_name(a) |> after_call"

      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "three args in anonymous function" do
      piped = """
      a
      |> function_name.(b, c)
      |> after_call
      """

      unpiped = "function_name.(a, b, c) |> after_call"

      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "single arg in anonymous function" do
      piped = """
      MyModule.f(a)
      |> function_name.()
      |> after_call
      """

      unpiped = "function_name.(MyModule.f(a)) |> after_call"

      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "function call piped into another function" do
      piped = """
      f(a)
      |> g(b, c)
      |> after_call
      """

      unpiped = "g(f(a), b, c) |> after_call"

      assert AST.from_pipe(piped) == {:ok, unpiped}
    end

    test "multi-line with \r as separator and \r\n inside strings raises syntax error" do
      # This test shows that the parser is limited to Elixir's parser's capabilities
      assert {:error, :invalid_code} = AST.from_pipe(~s{X.Y.Z.function_name(\r1,\r"asdf\nghjk")})
    end
  end
end
