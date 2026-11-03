using Empty.scripts.auth;
using Xunit;

public class AuthValidatorTests
{
	private readonly AuthValidator _validator = new();

	private static AuthData Data(string email, string password) =>
		new AuthData { Email = email, Password = password };

	[Fact]
	public void ValidCredentials_Pass()
	{
		Assert.True(_validator.Validate(Data("player@example.com", "password123")).IsValid);
	}

	[Theory]
	[InlineData("")]
	[InlineData(null)]
	public void EmptyEmail_Fails_WithMessage(string email)
	{
		var result = _validator.Validate(Data(email, "password123"));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Email is required");
	}

	[Theory]
	[InlineData("not-an-email")]
	[InlineData("missing@")]
	[InlineData("@missing.com")]
	public void MalformedEmail_Fails(string email)
	{
		Assert.False(_validator.Validate(Data(email, "password123")).IsValid);
	}

	[Theory]
	[InlineData("")]
	[InlineData(null)]
	public void EmptyPassword_Fails_WithMessage(string password)
	{
		var result = _validator.Validate(Data("player@example.com", password));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Password is required");
	}

	[Fact]
	public void ShortPassword_Fails_WithMessage()
	{
		var result = _validator.Validate(Data("player@example.com", "1234567"));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Password must be at least 8 characters");
	}

	[Fact]
	public void EightCharacterPassword_Passes()
	{
		Assert.True(_validator.Validate(Data("player@example.com", "12345678")).IsValid);
	}

	[Theory]
	[InlineData("' OR 1=1 --")]
	[InlineData("a@b.com'; DROP TABLE users;--")]
	[InlineData("<script>alert(1)</script>")]
	[InlineData("player@example.com\0")]
	[InlineData("player@exam\nple.com")]
	public void InjectionStyleEmail_IsRejected(string email)
	{
		Assert.False(_validator.Validate(Data(email, "password123")).IsValid);
	}

	[Theory]
	[InlineData("' OR '1'='1' --")]
	[InlineData("'; DROP TABLE users;--")]
	[InlineData("<script>alert(1)</script>")]
	public void InjectionStylePassword_IsAcceptedAsPlainText(string password)
	{
		// Passwords are opaque secrets sent to Supabase, so special characters are legitimate.
		Assert.True(_validator.Validate(Data("player@example.com", password)).IsValid);
	}

	[Fact]
	public void ApostropheInEmail_IsAllowed()
	{
		// Valid per RFC (e.g. o'brien@example.com); safe because Supabase parameterizes queries.
		Assert.True(_validator.Validate(Data("o'brien@example.com", "password123")).IsValid);
	}

	[Fact]
	public void PasswordWithControlCharacter_Fails()
	{
		Assert.False(_validator.Validate(Data("player@example.com", "pass\0word123")).IsValid);
	}

	[Fact]
	public void Email_SurroundingWhitespace_IsTrimmed()
	{
		var data = Data("  player@example.com \t", "password123");
		Assert.Equal("player@example.com", data.Email);
		Assert.True(_validator.Validate(data).IsValid);
	}

	[Fact]
	public void WhitespaceOnlyEmail_Fails()
	{
		var result = _validator.Validate(Data("   ", "password123"));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Email is required");
	}

	[Fact]
	public void WhitespaceOnlyPassword_Fails()
	{
		Assert.False(_validator.Validate(Data("player@example.com", "         ")).IsValid);
	}

	[Fact]
	public void PasswordWithInnerSpaces_IsNotTrimmed()
	{
		var data = Data("player@example.com", "  pass word  ");
		Assert.Equal("  pass word  ", data.Password);
		Assert.True(_validator.Validate(data).IsValid);
	}

	[Fact]
	public void VeryLongEmail_Fails()
	{
		var email = new string('a', 250) + "@example.com";
		var result = _validator.Validate(Data(email, "password123"));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Email must be at most 254 characters");
	}

	[Fact]
	public void PasswordAtMaxLength_Passes_AndOverFails()
	{
		Assert.True(_validator.Validate(Data("player@example.com", new string('a', 72))).IsValid);

		var result = _validator.Validate(Data("player@example.com", new string('a', 73)));
		Assert.False(result.IsValid);
		Assert.Contains(result.Errors, e => e.ErrorMessage == "Password must be at most 72 characters");
	}

	[Fact]
	public void HugeInput_DoesNotThrow_AndFails()
	{
		var result = _validator.Validate(Data(new string('a', 1_000_000), new string('b', 1_000_000)));
		Assert.False(result.IsValid);
	}

	[Theory]
	[InlineData("pässwörd日本語")]
	[InlineData("пароль12345")]
	public void UnicodePassword_Passes(string password)
	{
		Assert.True(_validator.Validate(Data("player@example.com", password)).IsValid);
	}
}
