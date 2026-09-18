using Godot;
using System;
using Supabase;

public partial class AuthMenu : Control
{
	[Export] private Control _loginPanel;
	[Export] private Control _signUpPanel;
	
	[Export] private LineEdit _loginEmail;
	[Export] private LineEdit _loginPassword;
	[Export] private Button _logInButton;
	[Export] private LinkButton _goToSignUpButton;
	
	[Export] private LineEdit _signUpEmail;
	[Export] private LineEdit _signUpPassword;
	[Export] private Button _signUpButton;
	[Export] private LinkButton _goToLoginButton;

	private Client _supabase;
	private AuthValidator _validator = new AuthValidator();
	
	// Called when the node enters the scene tree for the first time.
	public override async void _Ready()
	{
		_logInButton.Pressed += OnLoginButtonPressed;
		_signUpButton.Pressed += OnSignUpButtonPressed;
		_goToSignUpButton.Pressed += OnGoToSignUpButtonPressed;
		_goToLoginButton.Pressed += OnGoToLoginButtonPressed;
		
		ShowLoginPanel();
		
		// URL and ENV_KEY will be added later when I learn about environment variables :)
		_supabase = new Client("URL", "ENV_KEY", new SupabaseOptions());
		await _supabase.InitializeAsync();
	}

	private void ShowLoginPanel()
	{
		_loginPanel.Visible = true;
		_signUpPanel.Visible = false;
	}

	private void ShowSignUpPanel()
	{
		_signUpPanel.Visible = true;
		_loginPanel.Visible = false;
	}

	private void OnGoToLoginButtonPressed()
	{
		ShowLoginPanel();
	}

	private void OnGoToSignUpButtonPressed()
	{
		ShowSignUpPanel();
	}

	private async void OnLoginButtonPressed()
	{
		var data = new AuthData
		{
			Email = _loginEmail.Text,
			Password = _loginPassword.Text
		};
		
		var result = _validator.Validate(data);

		if (!result.IsValid)
			return;
		
		_signUpButton.Disabled = true;

		try
		{
			var session = await _supabase.Auth.SignUp(data.Email, data.Password);
		}
		catch (Exception e)
		{
			Console.WriteLine(e);
			throw;
		}
	}

	private async void OnSignUpButtonPressed()
	{
		
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}
}
