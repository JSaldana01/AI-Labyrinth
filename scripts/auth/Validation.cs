using Godot;
using System;
using FluentValidation;

public class AuthData
{
	public string Email { get; set; }
	public string Password { get; set; }
}

public class AuthValidator : AbstractValidator<AuthData>
{
	private int _minPassLength = 8;
	public AuthValidator()
	{
		RuleFor(x => x.Email)
			.EmailAddress()
			.NotEmpty().WithMessage("Email is required");
		
		RuleFor(x => x.Password)
			.NotEmpty().WithMessage("Password is required")
			.MinimumLength(_minPassLength).WithMessage("Password must be at least " + _minPassLength + " characters");
		
		// Use below if we ever want confirming password to be a thing, I think (no)
		// RuleSet("SignUp", () =>
		// {
		// 	RuleFor(x)
		// })
	}
}
