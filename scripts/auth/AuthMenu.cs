using Godot;
using System;
using System.Linq;
using Supabase;
using Supabase.Gotrue.Exceptions;

public partial class AuthMenu : Control
{
	[Export] private Control _loginPanel;
	[Export] private Control _signUpPanel;
	
	[Export] private LineEdit _loginEmail;
	[Export] private LineEdit _loginPassword;
	[Export] private Button _logInButton;
	[Export] private Label _loginEmailErrorLabel;
	[Export] private Label _loginPasswordErrorLabel;
	[Export] private LinkButton _goToSignUpButton;
	
	[Export] private LineEdit _signUpEmail;
	[Export] private LineEdit _signUpPassword;
	[Export] private Button _signUpButton;
	[Export] private Label _signUpEmailErrorLabel;
	[Export] private Label _signUpPasswordErrorLabel;
	[Export] private LinkButton _goToLoginButton;

	[Export] private Button _testLoginButton;

	private const string MazeScenePath = "res://tscn/maze/maze.tscn";

	private AuthValidator _validator = new AuthValidator();
	
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		_logInButton.Pressed += OnLoginButtonPressed;
		_signUpButton.Pressed += OnSignUpButtonPressed;
		_goToSignUpButton.Pressed += OnGoToSignUpButtonPressed;
		_goToLoginButton.Pressed += OnGoToLoginButtonPressed;
		_testLoginButton.Pressed += OnTestLoginButtonPressed;
		
		ShowLoginPanel();
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

		// Simple validation, return if invalid
		if (!result.IsValid)
		{
			_loginEmailErrorLabel.Text = result.Errors.FirstOrDefault(e => e.PropertyName == "Email")?.ErrorMessage;
			_loginPasswordErrorLabel.Text = result.Errors.FirstOrDefault(e => e.PropertyName == "Password")?.ErrorMessage;
			return;
		}
		
		_loginEmailErrorLabel.Text = "";
		_loginPasswordErrorLabel.Text = "";
		
		try
		{
			// Session if its needed
			var login = await DBManager.Supabase.Auth.SignIn(data.Email, data.Password);
			GD.Print(login);
			GetTree().ChangeSceneToFile(MazeScenePath);
		}
		catch (Exception e)
		{
			GD.PrintErr($"Login Failed: {e.Message}");
		}
	}

	// Bypasses Supabase auth so the maze can be reached without a real account.
	private void OnTestLoginButtonPressed()
	{
		GetTree().ChangeSceneToFile(MazeScenePath);
	}

	private async void OnSignUpButtonPressed()
	{
		var data = new AuthData
		{
			Email = _signUpEmail.Text,
			Password = _signUpPassword.Text
		};
		
		var result = _validator.Validate(data);

		// Make sure validator for email and password are the first checks done and returned if invalid
		if (!result.IsValid)
		{
			_signUpEmailErrorLabel.Text = result.Errors.FirstOrDefault(e => e.PropertyName == "Email")?.ErrorMessage;
			_signUpPasswordErrorLabel.Text = result.Errors.FirstOrDefault(e => e.PropertyName == "Password")?.ErrorMessage;
			GD.PrintErr($"Sign Up Failed: {result.Errors.FirstOrDefault(e => e.PropertyName == "Email")?.ErrorMessage}" +  result.Errors.FirstOrDefault(e => e.PropertyName == "Password")?.ErrorMessage);
			return;
		}
		
		// Sign up went good
		_signUpEmailErrorLabel.Text = "";
		_signUpPasswordErrorLabel.Text = "";


		try
		{
			var res = await DBManager.Supabase.Auth.SignUp(data.Email, data.Password);
			GD.Print(res);
			GetTree().ChangeSceneToFile(MazeScenePath);
		}
		catch (GotrueException e)
		{
			Console.WriteLine("User already exists! Full exception:");
			Console.WriteLine(e);
			throw;
		}
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}
}
