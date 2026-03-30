import UIKit

class HomeViewController: UITableViewController {

    let demoList = [
        ("Big Buck Bunny", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
        ("Sintel", "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Demo"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        demoList.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = demoList[indexPath.row].0
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        let vc = PlayerViewController()
        vc.url = demoList[indexPath.row].1
        navigationController?.pushViewController(vc, animated: true)
    }
}
