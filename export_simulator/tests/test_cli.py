from transit_sim.cli import main


def test_simulate_cli(tmp_path, capsys):
    out = tmp_path / "run.csv"
    assert main(["simulate", "--species", "guppy", "--count", "20", "--mass", "0.3", "--water", "0.4",
                 "--gas", "1.2", "--hours", "24", "--csv", str(out)]) == 0
    assert "Predicted survival" in capsys.readouterr().out
    assert out.read_text().startswith("t,do,tan")


def test_unknown_anaesthetic(capsys):
    assert main(["simulate", "--count", "1", "--mass", "1", "--water", "1", "--gas", "1", "--hours", "1",
                 "--anaesthetic", "nope"]) == 2
