using System.Linq;
using FluentValidation;

namespace Empty.scripts.auth;

public class AuthData
{
	private string _email;

	// Surrounding whitespace is stripped so pasted emails with stray spaces still work.
	public string Email
	{
		get => _email;
		set => _email = value?.Trim();
	}

	public string Password { get; set; }
}

public class AuthValidator : AbstractValidator<AuthData>
{
	private int _minPassLength = 8;
	// 72 is bcrypt's byte limit, which Supabase uses for passwords; 254 is the max email length.
	private const int MaxPassLength = 72;
	private const int MaxEmailLength = 254;

	public AuthValidator()
	{
		RuleFor(x => x.Email)
			.EmailAddress()
			.NotEmpty().WithMessage("Email is required")
			.Must(e => e == null || !e.Any(c => char.IsControl(c) || char.IsWhiteSpace(c)))
				.WithMessage("Email must not contain spaces or control characters")
			.MaximumLength(MaxEmailLength).WithMessage("Email must be at most " + MaxEmailLength + " characters");
		
		RuleFor(x => x.Password)
			.NotEmpty().WithMessage("Password is required")
			.Must(p => p == null || !p.Any(char.IsControl))
				.WithMessage("Password must not contain control characters")
			.MinimumLength(_minPassLength).WithMessage("Password must be at least " + _minPassLength + " characters")
			.MaximumLength(MaxPassLength).WithMessage("Password must be at most " + MaxPassLength + " characters");
		
		// Use below if we ever want confirming password to be a thing, I think (no)
		// RuleSet("SignUp", () =>
		// {
		// 	RuleFor(x)
		// })
	}
}
